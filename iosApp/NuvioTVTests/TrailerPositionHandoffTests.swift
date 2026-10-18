import AVFoundation
import XCTest
@testable import NuvioTV

/// BUG-130 (u/an_angry_Moose, 2026-10-02): the full-screen trailer continues from the Detail
/// background copy's position instead of replaying the seconds already watched.
@MainActor
final class TrailerPositionHandoffTests: XCTestCase {
    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    func testSameStreamResumesOnce() {
        let handoff = TrailerPositionHandoff()
        handoff.record(url: "http://127.0.0.1:8230/a", time: t(6.4), duration: t(150))
        XCTAssertEqual(handoff.take(url: "http://127.0.0.1:8230/a")?.seconds ?? 0, 6.4, accuracy: 0.01)
        XCTAssertNil(handoff.take(url: "http://127.0.0.1:8230/a"), "consumed")
    }

    func testAnotherStreamOrStaleEntryStartsFromZero() {
        let handoff = TrailerPositionHandoff()
        handoff.record(url: "a", time: t(6), duration: t(150))
        XCTAssertNil(handoff.take(url: "b"), "a row clip is a different stream")
        handoff.record(url: "a", time: t(6), duration: t(150))
        XCTAssertNil(handoff.take(url: "a", now: ProcessInfo.processInfo.systemUptime + TrailerPositionHandoff.freshness + 1))
    }

    func testNearTheStartOrTheEndIsNotCarried() {
        XCTAssertFalse(TrailerPositionHandoff.isUsable(time: t(0.4), duration: t(150)))
        XCTAssertFalse(TrailerPositionHandoff.isUsable(time: t(148), duration: t(150)))
        XCTAssertTrue(TrailerPositionHandoff.isUsable(time: t(20), duration: t(150)))
        XCTAssertTrue(TrailerPositionHandoff.isUsable(time: t(20), duration: .indefinite), "unknown duration still carries")
        XCTAssertFalse(TrailerPositionHandoff.isUsable(time: .invalid, duration: nil))
    }
}
