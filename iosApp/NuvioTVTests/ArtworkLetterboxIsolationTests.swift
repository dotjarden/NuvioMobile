import XCTest
import UIKit
@testable import NuvioTV

/// Batch P (P1-1): the NuvioTV target defaults to MainActor isolation, which silently pulled the
/// letterbox scan back onto the main thread even from `Task.detached`. `ArtworkLetterbox` is now
/// `nonisolated`; these guard that it stays off main and still measures bars.
final class ArtworkLetterboxIsolationTests: XCTestCase {
    /// 256 x 144 mid-grey picture with 18 px black bars top and bottom.
    private func barredImage() -> UIImage {
        let size = CGSize(width: 256, height: 144)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 18, width: 256, height: 108))
        }
    }

    func testZoomRunsOffTheMainThread() async {
        let image = barredImage()
        let key = UUID().uuidString
        let onMain = await Task.detached { () -> Bool in
            _ = ArtworkLetterbox.zoom(for: image, cacheKey: key)
            return Thread.isMainThread
        }.value
        XCTAssertFalse(onMain)
    }

    func testZoomStillMeasuresBars() async {
        let image = barredImage()
        let key = UUID().uuidString
        let zoom = await Task.detached { ArtworkLetterbox.zoom(for: image, cacheKey: key) }.value
        XCTAssertGreaterThan(zoom, 1.2)
        XCTAssertLessThanOrEqual(zoom, 1.45)
    }
}
