import Foundation
import XCTest
@testable import NuvioTV

final class RemoteSetupServerTests: XCTestCase {
    private func proposal(_ json: String) throws -> RemoteSetupServer.Proposal {
        try JSONDecoder().decode(RemoteSetupServer.Proposal.self, from: Data(json.utf8))
    }

    func testProposalRejectsInvalidURLsAndDuplicateRows() throws {
        XCTAssertNotNil(try proposal(#"{"addons":[{"url":"javascript:alert(1)"}]}"#).validationError)
        XCTAssertNotNil(try proposal(#"{"badgeUrls":["file:///tmp/pack.json"]}"#).validationError)
        XCTAssertNotNil(try proposal(#"{"rowOrder":["one","one"]}"#).validationError)
        XCTAssertNotNil(try proposal(#"{"rowOrder":["one"],"disabledRowKeys":["two"]}"#).validationError)
        XCTAssertNil(try proposal(#"{"addons":[{"url":"https://example.invalid/manifest.json","enabled":false}],"rowOrder":["one"],"disabledRowKeys":["one"]}"#).validationError)
        XCTAssertNil(try proposal(#"{"tmdbKey":"new-key"}"#).validationError)
    }

    @MainActor func testApprovalWaitsForCompletionAndReportsImportFailure() async throws {
        let server = RemoteSetupServer()
        defer { server.stop() }
        let port = await withCheckedContinuation { continuation in server.start { continuation.resume(returning: $0) } }
        let base = try XCTUnwrap(port)
        let token = try XCTUnwrap(server.sessionToken)
        server.updateState(Data(#"{"addons":[],"rows":[],"badgePacks":[]}"#.utf8))
        let state = try await request(base, token: token, path: "/api/state")
        let revision = try XCTUnwrap(state.1["revision"] as? String)
        let sent = try await request(base, token: token, path: "/api/apply", body: ["baseRevision": revision, "badgeUrls": ["https://example.invalid/pack.json"]])
        let id = try XCTUnwrap(sent.1["id"] as? String)
        XCTAssertEqual(sent.0, 200)
        XCTAssertTrue(server.beginApplying(id: id))
        var status = try await request(base, token: token, path: "/api/status/\(id)")
        XCTAssertEqual(status.1["status"] as? String, "applying")
        let duplicate = try await request(base, token: token, path: "/api/apply", body: ["tmdbKey": "test"])
        XCTAssertEqual(duplicate.0, 409)
        server.complete(id: id, errors: ["Badge pack: Couldn't import."])
        status = try await request(base, token: token, path: "/api/status/\(id)")
        XCTAssertEqual(status.1["status"] as? String, "failed")
        XCTAssertEqual(status.1["errors"] as? [String], ["Badge pack: Couldn't import."])
        XCTAssertEqual(status.1["started"] as? Bool, true)
    }

    @MainActor func testStaleSnapshotCannotOverwriteTVAndTokenIsRequired() async throws {
        let server = RemoteSetupServer()
        defer { server.stop() }
        let port = await withCheckedContinuation { continuation in server.start { continuation.resume(returning: $0) } }
        let base = try XCTUnwrap(port)
        let token = try XCTUnwrap(server.sessionToken)
        server.updateState(Data(#"{"addons":[],"rows":[]}"#.utf8))
        let state = try await request(base, token: token, path: "/api/state")
        let revision = try XCTUnwrap(state.1["revision"] as? String)
        let sent = try await request(base, token: token, path: "/api/apply", body: ["baseRevision": revision, "tmdbKey": "test"])
        let id = try XCTUnwrap(sent.1["id"] as? String)
        server.updateState(Data(#"{"addons":[],"rows":[{"key":"new"}]}"#.utf8))
        XCTAssertFalse(server.beginApplying(id: id))
        let status = try await request(base, token: token, path: "/api/status/\(id)")
        XCTAssertEqual(status.1["status"] as? String, "failed")
        XCTAssertEqual(status.1["started"] as? Bool, false)
        let stale = try await request(base, token: token, path: "/api/apply", body: ["baseRevision": revision])
        XCTAssertEqual(stale.0, 409)
        let forbidden = try await request(base, token: "wrong", path: "/api/state")
        XCTAssertEqual(forbidden.0, 403)
    }

    @MainActor func testNewAddonKeepsRequestedOrderAndDisabledState() async {
        typealias Entry = RemoteSetupServer.Proposal.AddonEntry
        var saved = [Entry(url: "old", enabled: true), Entry(url: "remove", enabled: true)]
        let desired = [Entry(url: "new", enabled: false), Entry(url: "old", enabled: true)]
        var operations: [String] = []
        let errors = await RemoteSetupAddonApplication.apply(desired, snapshot: { saved },
            install: { url in
                await Task.yield()
                saved.append(Entry(url: url, enabled: true)); operations.append("install"); return nil
            }, remove: { url in saved.removeAll { $0.url == url }; operations.append("remove") },
            setEnabled: { url, enabled in saved = saved.map { $0.url == url ? Entry(url: url, enabled: enabled) : $0 } },
            move: { from, to in saved.insert(saved.remove(at: from), at: to) })
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(saved.map(\.url), ["new", "old"])
        XCTAssertEqual(saved.first?.enabled, false)
        XCTAssertEqual(operations, ["install", "remove"])
    }

    @MainActor func testFailedReplacementKeepsWorkingAddonAndReportsError() async {
        typealias Entry = RemoteSetupServer.Proposal.AddonEntry
        var saved = [Entry(url: "working", enabled: true)]
        let errors = await RemoteSetupAddonApplication.apply([Entry(url: "broken", enabled: true)],
            snapshot: { saved }, install: { _ in "Error Domain=NSURLErrorDomain UserInfo=..." },
            remove: { url in saved.removeAll { $0.url == url } }, setEnabled: { _, _ in }, move: { _, _ in })
        XCTAssertEqual(saved.map(\.url), ["working"])
        XCTAssertEqual(errors.count, 2)
        XCTAssertFalse(errors.joined().contains("NSURLErrorDomain"))
    }

    @MainActor func testInheritedAddonWriteDoesNotClaimSuccess() async {
        typealias Entry = RemoteSetupServer.Proposal.AddonEntry
        let saved = [Entry(url: "primary", enabled: true)]
        let errors = await RemoteSetupAddonApplication.apply([], snapshot: { saved },
            install: { _ in nil }, remove: { _ in }, setEnabled: { _, _ in }, move: { _, _ in })
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("profile"))
    }

    private func request(_ port: UInt16, token: String, path: String, body: [String: Any]? = nil) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.setValue(token, forHTTPHeaderField: "X-Setup-Token")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
}
