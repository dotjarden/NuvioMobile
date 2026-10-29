import XCTest
import SharedCore
@testable import NuvioTV

final class SyncLineCueLoaderTests: XCTestCase {
    func testDecodeUTF8() {
        XCTAssertEqual(SyncLineCueLoader.decode(Data("héllo".utf8)), "héllo")
    }

    func testDecodeLatin1Fallback() {
        // 0xE9 alone is invalid UTF-8; ISO Latin-1 reads it as "é".
        XCTAssertEqual(SyncLineCueLoader.decode(Data([0xE9])), "é")
    }

    func testDecodeUTF16LEWithBOM() async throws {
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nHello\n\n"
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(srt.data(using: .utf16LittleEndian)))
        XCTAssertEqual(SyncLineCueLoader.decode(data)?.hasPrefix("1\n00:00:01"), true)
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("sync-line-\(UUID().uuidString).srt")
        try data.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let cues = await SyncLineCueLoader.load(source: path)
        XCTAssertEqual(cues?.count, 1)
        XCTAssertEqual(cues?.first?.startTimeMs, 1000)
    }

    func testLoadParsesLocalSRTFile() async throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        First line

        2
        00:00:04,000 --> 00:00:06,000
        Second line

        3
        00:00:07,000 --> 00:00:09,000
        Third line

        """
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("sync-line-\(UUID().uuidString).srt")
        try srt.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let cues = await SyncLineCueLoader.load(source: path)
        XCTAssertEqual(cues?.count, 3)
        XCTAssertEqual(cues?.first?.startTimeMs, 1000)
    }

    func testLoadVTTStringWithoutNetwork() async {
        let vtt = "WEBVTT\n\n00:00:02.000 --> 00:00:04.000\nHello\n\n00:00:05.000 --> 00:00:06.000\nWorld\n"
        let cues = await SyncLineCueLoader.load(vtt: vtt, fallbackURL: nil)
        XCTAssertEqual(cues?.count, 2)
        XCTAssertEqual(cues?.first?.startTimeMs, 2000)
    }

    func testLoadReturnsNilForMissingFile() async {
        let cues = await SyncLineCueLoader.load(source: "/nonexistent/path/missing-\(UUID().uuidString).srt")
        XCTAssertNil(cues)
    }
}
