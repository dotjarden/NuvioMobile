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

    /// Review r1 P3-5: a runtime `Thread.isMainThread` read after the call cannot detect a hop (the
    /// task is back on its own executor by then), and in Swift 5 mode a MainActor call from a
    /// detached task only warns. The assertion that holds is static: `zoom` is called from a
    /// synchronous `@Sendable` closure, which is a compile error ("call to main actor-isolated ...
    /// in a synchronous nonisolated context") if `ArtworkLetterbox` regains main-actor isolation. The on-device check is the rig's
    /// `ArtworkLetterbox.measuredZoom` main-thread profile list (`timeprofile.py`).
    func testZoomIsUsableFromANonisolatedSendableContext() async {
        let scan: @Sendable (UIImage, String) -> CGFloat = { ArtworkLetterbox.zoom(for: $0, cacheKey: $1) }
        let image = barredImage()
        let key = UUID().uuidString
        let zoom = await Task.detached { scan(image, key) }.value
        XCTAssertGreaterThan(zoom, 1)
    }

    func testZoomStillMeasuresBars() async {
        let image = barredImage()
        let key = UUID().uuidString
        let zoom = await Task.detached { ArtworkLetterbox.zoom(for: image, cacheKey: key) }.value
        XCTAssertGreaterThan(zoom, 1.2)
        XCTAssertLessThanOrEqual(zoom, 1.45)
    }
}
