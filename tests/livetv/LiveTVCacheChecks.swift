import Foundation
@main struct CacheChecks {
    static func main() async {
        let profile = "cache-test-" + UUID().uuidString
        let source = LiveTVSource(name: "Synthetic", kind: .m3u, address: "https://fixture.invalid/playlist?token=private-fixture")
        let channel = LiveTVChannel(id: "fixture", sourceID: source.id, name: "Test", group: "Test", logo: nil, guideID: "guide", url: URL(string: "https://fixture.invalid/private-stream")!)
        let fingerprint = LiveTVCache.fingerprint([source])
        let cache = LiveTVCache.shared
        await cache.write(.init(fingerprint: fingerprint, date: Date(), channels: [channel], programmes: [:]), profile: profile)
        let restored = await cache.read(profile: profile, fingerprint: fingerprint)
        precondition(restored?.channels == [channel], "Cached channels must survive a cache read")
        let wrongSource = await cache.read(profile: profile, fingerprint: "changed-source")
        precondition(wrongSource == nil, "Edited sources must reject old cached credentials")
        let otherProfile = await cache.read(profile: profile + "-other", fingerprint: fingerprint)
        precondition(otherProfile == nil, "Profiles must not share cached sources")
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveTV").appendingPathComponent(LiveTVIdentity.digest(profile) + ".cache")
        let bytes = try! Data(contentsOf: file)
        precondition(bytes.range(of: Data("private-stream".utf8)) == nil, "Cached URLs must be encrypted")
        await cache.write(.init(fingerprint: fingerprint, date: Date().addingTimeInterval(-8 * 86400), channels: [channel], programmes: [:]), profile: profile)
        let expired = await cache.read(profile: profile, fingerprint: fingerprint)
        precondition(expired == nil, "Expired caches must be refreshed")
        await cache.remove(profile: profile)
        print("PASS: encrypted cache round trip, source invalidation, profile isolation, expiry and cleanup")
    }
}
