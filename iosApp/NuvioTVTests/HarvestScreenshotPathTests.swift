import XCTest
@testable import NuvioTV

/// P3-F9 (docs/research/player-p4-rss-retention-2026-10-15.md): the harvest uses mpv's software
/// screenshot only for SDR frames, and the thumbnail is scaled from borrowed bytes.
final class HarvestScreenshotPathTests: XCTestCase {
    func testSoftwareOnlyForKnownSDR() {
        XCTAssertTrue(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "bt.1886", colormatrix: "bt.709"))
        XCTAssertTrue(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "srgb", colormatrix: nil))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "pq", colormatrix: "bt.2020-ncl"))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "HLG", colormatrix: "bt.2020-ncl"))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "bt.1886", colormatrix: "dolbyvision"))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: nil, colormatrix: "bt.709"), "unknown = HDR")
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "", colormatrix: nil))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: true, gamma: "auto", colormatrix: nil))
        XCTAssertFalse(HarvestScreenshotPath.useSoftware(enabled: false, gamma: "bt.1886", colormatrix: "bt.709"), "switch off")
    }

    /// P4-F3: the software path captured nothing on the Apple TV, so unset = Video Renderer.
    func testSwitchDefaultsToRenderer() {
        let defaults = UserDefaults(suiteName: "HarvestScreenshotPathTests")!
        defaults.removePersistentDomain(forName: "HarvestScreenshotPathTests")
        XCTAssertFalse(HarvestScreenshotPath.defaultSoftware)
        XCTAssertFalse(HarvestScreenshotPath.softwareEnabled(defaults))
        defaults.set(true, forKey: HarvestScreenshotPath.defaultsKey)
        XCTAssertTrue(HarvestScreenshotPath.softwareEnabled(defaults))
        defaults.set(false, forKey: HarvestScreenshotPath.defaultsKey)
        XCTAssertFalse(HarvestScreenshotPath.softwareEnabled(defaults))
        defaults.removePersistentDomain(forName: "HarvestScreenshotPathTests")
    }

    /// P4-F3: a software-path capture with no frame, or an empty one, is retaken on the renderer;
    /// a good software frame is kept, and a renderer-path miss never "falls back".
    func testSoftwareMissFallsBackToRenderer() {
        let good = MPVHarvestCapture(width: 1920, height: 1080, format: "bgr0", thumb: nil)
        let emptyW = MPVHarvestCapture(width: 0, height: 1080, format: "bgr0", thumb: nil)
        let emptyH = MPVHarvestCapture(width: 1920, height: 0, format: "-", thumb: nil)
        XCTAssertTrue(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: true, frame: nil))
        XCTAssertTrue(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: true, frame: emptyW))
        XCTAssertTrue(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: true, frame: emptyH))
        XCTAssertFalse(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: true, frame: good))
        XCTAssertFalse(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: false, frame: nil))
        XCTAssertFalse(HarvestScreenshotPath.fallsBackToRenderer(onSoftware: false, frame: good))
    }

    func testSyntheticSizeParse() {
        XCTAssertEqual(HarvestScreenshotPath.parseSize("2560x1070")?.width, 2560)
        XCTAssertEqual(HarvestScreenshotPath.parseSize("2560X1070")?.height, 1070)
        XCTAssertNil(HarvestScreenshotPath.parseSize(nil))
        XCTAssertNil(HarvestScreenshotPath.parseSize("2560"))
        XCTAssertNil(HarvestScreenshotPath.parseSize("0x0"))
    }

    /// The borrowed-bytes scaler gives the same picture as the Data one, and the result owns its
    /// pixels: the source buffer can be overwritten afterwards without changing the thumbnail.
    func testBorrowedScaleMatchesAndOwnsItsPixels() throws {
        let w = 1280, h = 534, stride = w * 4
        var buffer = [UInt8](repeating: 0x80, count: stride * h)
        let thumb = try XCTUnwrap(buffer.withUnsafeBytes {
            PreviewFrameScaler.makeThumbnail(width: w, height: h, stride: stride, format: "bgr0", bytes: $0)
        })
        let viaData = try XCTUnwrap(PreviewFrameScaler.makeThumbnail(
            MPVRawFrame(width: w, height: h, stride: stride, format: "bgr0", bytes: Data(buffer))))
        XCTAssertEqual(thumb.width, viaData.width)
        XCTAssertEqual(thumb.height, viaData.height)
        for i in buffer.indices { buffer[i] = 0 }
        let pixel = try XCTUnwrap(thumb.dataProvider?.data as Data?)
        XCTAssertEqual(pixel[pixel.count / 2], 0x80, "the thumbnail still reads the original grey")
        XCTAssertNil(buffer.withUnsafeBytes {
            PreviewFrameScaler.makeThumbnail(width: w, height: h, stride: stride, format: "p010", bytes: $0)
        }, "unsupported format")
    }
}
