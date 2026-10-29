import XCTest
@testable import NuvioTV

/// Polish batch D1/D3: the pure text rules behind a stream row's headline and fact lines
/// (`StreamRowFacts`). Expected strings come straight from the spec tables (2.4, 2.5, 2.7, 5).
final class StreamRowFactLinesTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    // MARK: - Headline (2.4)

    func testHeadlineFloorsToTheStep() {
        let table: [(Int, String)] = [
            (4320, "4K"), (2160, "4K"), (2159, "1440p"), (1600, "1440p"), (1440, "1440p"),
            (1439, "1080p"), (1080, "1080p"), (1079, "720p"), (720, "720p"),
            (719, "SD"), (576, "SD"), (480, "SD"), (360, "SD"), (1, "SD"),
        ]
        for (resolution, expected) in table {
            XCTAssertEqual(StreamRowFacts.headline(forResolution: resolution), expected, "\(resolution)")
        }
    }

    func testNoHeadlineWithoutAPositiveResolution() {
        XCTAssertNil(StreamRowFacts.headline(forResolution: nil))
        XCTAssertNil(StreamRowFacts.headline(forResolution: 0))
        XCTAssertNil(StreamRowFacts.headline(forResolution: -1))
    }

    // MARK: - HDR mark (2.5)

    func testHdrMarkTable() {
        let table: [(String, String)] = [
            ("DV", "DV"), ("HDR", "HDR"), ("HDR10", "HDR10"), ("HDR10+", "HDR10+"), ("HLG", "HLG"),
            ("DV HDR", "DV · HDR"), ("DV HDR10", "DV · HDR10"), ("DV HDR10+", "DV · HDR10+"),
            ("DV HLG", "DV · HLG"),
        ]
        for (hdr, mark) in table {
            XCTAssertEqual(StreamRowFacts.hdrMark(hdr), mark, hdr)
        }
        XCTAssertNil(StreamRowFacts.hdrMark(nil))
        XCTAssertNil(StreamRowFacts.hdrMark("  "))
    }

    // MARK: - Fact line 1

    func testVideoFacts() {
        XCTAssertEqual(StreamRowFacts.videoFacts(sourceType: "WEB-DL", codec: "HEVC"), ["WEB-DL", "HEVC"])
        XCTAssertEqual(StreamRowFacts.videoFacts(sourceType: nil, codec: "HEVC"), ["HEVC"])
        XCTAssertEqual(StreamRowFacts.videoFacts(sourceType: "BluRay", codec: nil), ["BluRay"])
        XCTAssertEqual(StreamRowFacts.videoFacts(sourceType: nil, codec: nil), [])
        XCTAssertEqual(StreamRowFacts.videoFacts(sourceType: " ", codec: ""), [])
    }

    // MARK: - Languages (2.7)

    func testLanguagesText() {
        XCTAssertEqual(StreamRowFacts.languagesText(["en"], locale: en), "English")
        XCTAssertEqual(StreamRowFacts.languagesText(["en", "es", "fr"], locale: en), "English, Spanish, French")
        XCTAssertEqual(StreamRowFacts.languagesText(["en", "es", "fr", "de", "it"], locale: en),
                       "English, Spanish, French +2")
        XCTAssertEqual(StreamRowFacts.languagesText(["en", "en"], locale: en), "English")
        XCTAssertEqual(StreamRowFacts.languagesText(["la"], locale: en), "Latino")
        XCTAssertEqual(StreamRowFacts.languagesText(["multi"], locale: en), "Multi")
        XCTAssertNil(StreamRowFacts.languagesText(["unknown"], locale: en))
        XCTAssertEqual(StreamRowFacts.languagesText(["unknown", "en"], locale: en), "English")
        XCTAssertEqual(StreamRowFacts.languagesText(["zz"], locale: en), "ZZ")
        XCTAssertNil(StreamRowFacts.languagesText([], locale: en))
    }

    func testLanguageNamesFollowTheLocaleAndStartUpperCase() {
        XCTAssertEqual(StreamRowFacts.languagesText(["en"], locale: Locale(identifier: "fr_FR")), "Anglais")
    }

    // MARK: - Audio line

    func testAudioFactsDropNilsAndKeepOrder() {
        XCTAssertEqual(StreamRowFacts.audioFacts(audio: "Atmos DD+ 5.1", languages: ["en"], locale: en),
                       ["Atmos DD+ 5.1", "English"])
        XCTAssertEqual(StreamRowFacts.audioFacts(audio: nil, languages: ["en"], locale: en), ["English"])
        XCTAssertEqual(StreamRowFacts.audioFacts(audio: "AAC", languages: [], locale: en), ["AAC"])
        XCTAssertEqual(StreamRowFacts.audioFacts(audio: nil, languages: ["unknown"], locale: en), [])
    }

    // MARK: - Cached part (5)

    func testCachedState() {
        XCTAssertEqual(StreamRowFacts.cachedState(cached: true, provider: "TB"), .instant(provider: "TB"))
        XCTAssertEqual(StreamRowFacts.cachedState(cached: true, provider: nil), .instant(provider: nil))
        XCTAssertEqual(StreamRowFacts.cachedState(cached: true, provider: ""), .instant(provider: nil))
        XCTAssertEqual(StreamRowFacts.cachedState(cached: false, provider: "TB"), .notCached)
        XCTAssertEqual(StreamRowFacts.cachedState(cached: false, provider: nil), .notCached)
        XCTAssertNil(StreamRowFacts.cachedState(cached: nil, provider: "TB"))
        XCTAssertNil(StreamRowFacts.cachedState(cached: nil, provider: nil))
    }

    func testCachedTextAndSymbol() {
        XCTAssertEqual(StreamRowFacts.cachedText(.instant(provider: "TB")), "TB Instant")
        XCTAssertEqual(StreamRowFacts.cachedText(.instant(provider: nil)), "Instant")
        XCTAssertEqual(StreamRowFacts.cachedText(.instant(provider: "")), "Instant")
        XCTAssertEqual(StreamRowFacts.cachedText(.notCached), "Not cached")
        XCTAssertEqual(StreamRowFacts.cachedSymbol(.instant(provider: "TB")), "checkmark.circle")
        XCTAssertEqual(StreamRowFacts.cachedSymbol(.instant(provider: nil)), "checkmark.circle")
        XCTAssertEqual(StreamRowFacts.cachedSymbol(.notCached), "arrow.down.circle")
    }

    func testTheJoinedAudioLineOfAFullStream() {
        let terms = StreamRowFacts.audioFacts(audio: "Atmos DD+ 5.1", languages: ["en"], locale: en)
            + [StreamRowFacts.cachedState(cached: true, provider: "TB").map(StreamRowFacts.cachedText)].compactMap { $0 }
        XCTAssertEqual(terms.joined(separator: " · "), "Atmos DD+ 5.1 · English · TB Instant")
    }
}
