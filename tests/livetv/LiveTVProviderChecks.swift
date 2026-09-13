import Foundation
@main struct ProviderChecks {
    static func main() async throws {
        let service = LiveTVService()
        let playlist = LiveTVSource(name: "Fixture", kind: .m3u, address: "http://127.0.0.1:8766/playlist.m3u")
        let m3u = try await service.load(playlist)
        precondition(m3u.channels.count == 1 && m3u.programmes.count == 1, "M3U and automatic relative XMLTV discovery")
        precondition(m3u.programmes[0].isCurrent(at: Date()), "current programme")
        let xtream = LiveTVSource(name: "Provider", kind: .xtream, address: "http://127.0.0.1:8766", username: "fixture user", password: "p&ss")
        let result = try await service.load(xtream)
        precondition(result.channels.count == 1 && result.programmes.count == 1, "Xtream channels and guide")
        precondition(result.channels[0].group == "Nature", "category mapping")
        precondition(result.channels[0].url.path.hasSuffix("/42.m3u8"), "native HLS URL")
        var invalid = xtream; invalid.password = "incorrect"
        do { _ = try await service.load(invalid); preconditionFailure("bad login accepted") } catch LiveTVError.authentication { }
        let fallback = try await service.load(LiveTVSource(name: "No guide", kind: .m3u, address: "http://127.0.0.1:8766/no-guide.m3u"))
        precondition(fallback.channels.count == 1 && fallback.guideWarning != nil, "EPG outage preserves channels")
        do { _ = try await service.load(LiveTVSource(name: "Missing", kind: .m3u, address: "http://127.0.0.1:8766/missing")); preconditionFailure("404 accepted") } catch LiveTVError.response(404) { }
        let start = Date()
        let delivery = ChannelDelivery()
        let slow = LiveTVSource(name: "Slow guide", kind: .m3u, address: "http://127.0.0.1:8766/slow.m3u")
        let slowResult = try await service.load(slow) { channels in
            await delivery.receive(channels, elapsed: Date().timeIntervalSince(start))
        }
        let early = await delivery.elapsed
        precondition(early != nil && early! < 1, "Channels must arrive before the slow guide")
        precondition(Date().timeIntervalSince(start) >= 2 && slowResult.programmes.count == 1, "Guide must still finish in the background")
        print("PASS: 10 HTTP provider integration checks (including usable channels before a slow guide)")
    }
}

actor ChannelDelivery {
    var elapsed: TimeInterval?
    func receive(_ channels: [LiveTVChannel], elapsed: TimeInterval) {
        precondition(channels.count == 1)
        self.elapsed = elapsed
    }
}
