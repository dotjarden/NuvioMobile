import Foundation

@main struct LiveTVParserChecks {
    static func main() throws {
        let source = LiveTVSource(name: "Fixture", kind: .m3u, address: "https://example.com/list/channels.m3u")
        let playlist = """
        \u{feff}#EXTM3U x-tvg-url="https://example.com/guide.xml"
        #EXTINF:-1 tvg-id="news" tvg-name="News, International" group-title="News" tvg-logo="https://example.com/logo.png",News HD
        #EXTVLCOPT:http-user-agent=TV Player
        #EXTVLCOPT:http-referrer=https://example.com/
        ../news.m3u8
        #EXTINF:-1 tvg-id="news",News SD
        https://example.com/sd.m3u8|User-Agent=Another%20Player
        #EXTINF:-1,Duplicate
        https://example.com/sd.m3u8
        #EXTINF:-1,Unsafe
        file:///etc/passwd
        #EXTINF:-1 tvg-name="Fallback"
        #EXTGRP:Documentary
        https://example.com/doc.m3u8
        """
        let channels = try M3UParser.parse(playlist, source: source)
        precondition(channels.count == 3, "deduplication and URL validation")
        precondition(channels[0].name == "News HD", "quoted comma must not terminate attributes")
        precondition(channels[0].url.absoluteString == "https://example.com/news.m3u8", "relative URLs")
        precondition(channels[0].headers["User-Agent"] == "TV Player", "VLC user agent")
        precondition(channels[0].headers["Referer"] == "https://example.com/", "VLC referrer")
        precondition(channels[1].headers["User-Agent"] == "Another Player", "URL-encoded headers")
        precondition(channels[0].id != channels[1].id, "same EPG ID supports HD/SD variants")
        precondition(channels[0].id.count == 64 && !channels[0].id.contains("https"), "opaque persisted identity")
        precondition(channels[2].name == "Fallback" && channels[2].group == "Documentary", "name/group fallbacks")
        precondition(channels[2].headers.isEmpty, "headers cannot leak to the next channel")
        do { _ = try M3UParser.parse("<html>error</html>", source: source); preconditionFailure("HTML accepted") } catch LiveTVError.invalidPlaylist { }
        do { _ = try M3UParser.parse("#EXTM3U\n# comment", source: source); preconditionFailure("empty playlist accepted") } catch LiveTVError.emptyChannels { }
        let now = ISO8601DateFormatter().date(from: "2026-09-08T00:30:00Z")!
        let xml = """
        <?xml version="1.0"?><tv>
        <programme channel="news" start="20260907200000 -0400" stop="20260907210000 -0400"><title>News &amp; Weather</title><desc>Tonight’s stories.</desc></programme>
        <programme channel="news" start="20260908010000 +0000" stop="20260908020000 +0000"><title>Next</title></programme>
        <programme channel="bad" start="invalid" stop="invalid"><title>Invalid</title></programme>
        <programme channel="bad" start="20260908020000 +0000" stop="20260908010000 +0000"><title>Backwards</title></programme>
        </tv>
        """
        let parser = XMLTVParser(now: now), programmes = try parser.parse(Data(xml.utf8))
        precondition(programmes.count == 2, "invalid programmes filtered")
        precondition(programmes[0].isCurrent(at: now), "timezone offsets")
        precondition(!programmes[0].isCurrent(at: programmes[0].end), "end boundary exclusive")
        precondition(programmes[0].title == "News & Weather", "XML entities")
        let repeated = try parser.parse(Data(xml.utf8)); precondition(repeated.count == 2, "parser reuse must clear state")
        do { _ = try XMLTVParser(now: now).parse(Data("<tv><programme>".utf8)); preconditionFailure("malformed XML accepted") } catch LiveTVError.invalidGuide { }
        print("PASS: 18 Live TV parser, identity, header, and guide checks")
    }
}
