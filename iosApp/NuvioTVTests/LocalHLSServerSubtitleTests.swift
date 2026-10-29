import XCTest
@testable import NuvioTV

/// P4 (B17, C-1, C-2): late subtitle renditions, the rebuild's start offset and the audio DEFAULT
/// following the selected track — all on the rendered master, no listener needed.
final class LocalHLSServerSubtitleTests: XCTestCase {
    private func map() throws -> SegmentMap {
        let kf: [Int64] = stride(from: 0, to: 20_000, by: 2_000).map { Int64($0) }
        return try XCTUnwrap(SegmentMap.build(keyframeTicks: kf, timeBaseNum: 1, timeBaseDen: 1000,
                                              totalDurationSec: 20, segDurSec: 4))
    }
    private let sig = VideoSignaling(codecs: "avc1.640028", supplementalCodecs: nil, videoRange: "SDR",
                                     width: 1920, height: 1080, frameRate: 24)
    private let english = SubtitleRendition(index: 0, name: "English", language: "en",
                                            source: .remote(URL(string: "https://subs.example.com/a.srt")!))
    private let audio = [
        AudioRendition(streamIndex: 1, name: "English", language: "en", channels: 2, codecToken: "mp4a.40.2", isDefault: true),
        AudioRendition(streamIndex: 2, name: "French", language: "fr", channels: 2, codecToken: "mp4a.40.2", isDefault: false),
    ]

    private func server(selected: Int? = nil) throws -> LocalHLSServer {
        LocalHLSServer(rootDir: FileManager.default.temporaryDirectory, map: try map(), signaling: sig,
                       audioRenditions: audio, selectedAudio: { selected }, bandwidth: 8_000_000,
                       subtitles: [english], subtitleFlags: [.legacy],
                       producingInfo: { (1, nil) }, requestReposition: { _ in })
    }

    private func mediaLines(_ master: String, type: String) -> [String] {
        master.components(separatedBy: "\n").filter { $0.hasPrefix("#EXT-X-MEDIA:TYPE=\(type)") }
    }

    func testSetSubtitlesAppendsAndKeepsExistingLines() throws {
        let s = try server()
        let before = try XCTUnwrap(s.renderedMasterPlaylist())
        let late = SubtitleRendition(index: 1, name: "German", language: "de",
                                     source: .remote(URL(string: "https://subs.example.com/b.srt")!))
        s.setSubtitles([english, late], flags: [.legacy, SubtitleRenditionFlags(autoselect: true, isDefault: false)])
        let after = try XCTUnwrap(s.renderedMasterPlaylist())
        let oldLines = mediaLines(before, type: "SUBTITLES")
        let newLines = mediaLines(after, type: "SUBTITLES")
        XCTAssertEqual(newLines.count, oldLines.count + 1)
        XCTAssertEqual(Array(newLines.prefix(oldLines.count)), oldLines)
        XCTAssertTrue(newLines.last?.contains("NAME=\"German\"") == true)
        XCTAssertTrue(newLines.last?.contains("sub-1.m3u8") == true)
        XCTAssertNotNil(s.renderedPlaylist(named: "sub-1.m3u8"))
    }

    func testStartOffset() throws {
        let s = try server()
        let plain = try XCTUnwrap(s.renderedMasterPlaylist())
        s.setStartOffset(312.5)
        let lines = try XCTUnwrap(s.renderedMasterPlaylist()).components(separatedBy: "\n")
        let v = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("#EXT-X-VERSION") })
        XCTAssertEqual(lines[v + 1], "#EXT-X-START:TIME-OFFSET=312.500,PRECISE=YES")
        s.setStartOffset(nil)
        XCTAssertEqual(s.renderedMasterPlaylist(), plain)
    }

    func testAudioDefaultFollowsSelection() throws {
        let second = mediaLines(try XCTUnwrap(try server(selected: 2).renderedMasterPlaylist()), type: "AUDIO")
        XCTAssertTrue(second.first { $0.contains("NAME=\"French\"") }?.contains("DEFAULT=YES") == true)
        XCTAssertTrue(second.first { $0.contains("NAME=\"English\"") }?.contains("DEFAULT=NO") == true)
        let unknown = mediaLines(try XCTUnwrap(try server(selected: nil).renderedMasterPlaylist()), type: "AUDIO")
        XCTAssertTrue(unknown.first { $0.contains("NAME=\"English\"") }?.contains("DEFAULT=YES") == true)
        XCTAssertTrue(unknown.first { $0.contains("NAME=\"French\"") }?.contains("DEFAULT=NO") == true)
    }
}
