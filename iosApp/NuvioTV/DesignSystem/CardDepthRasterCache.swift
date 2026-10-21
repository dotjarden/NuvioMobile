import SwiftUI
import UIKit

/// W3-13 (UX-16 / BUG-153 remainder), render variant 2 of `-debug.cardDepthRender`
/// (`HomePerfKnobs.CardDepthRender.rasterCache`): Card Depth's two gradient layers as bitmaps,
/// rendered ONCE per key with `UIGraphicsImageRenderer` and shared by every card drawing the same
/// key, instead of CoreGraphics re-filling both gradients on the CPU for every card mount
/// (`argb32_shade_axial_RGB` in Wave 0's Time Profiler).
///
/// - The rail is rendered WHITE at the stop alphas. `CardDepthOverlay` tints it with
///   `.colorMultiply`, so one bitmap serves every poster colour (`CardDepthStyle.multipliedRailStop`).
/// - The sheen is keyed apart from the rail, so one sheen bitmap serves every edge strength.
/// - The geometry is SwiftUI's own: the rail strokes `shape.inset(by: lineWidth / 2)` at `lineWidth`
///   (butt caps, miter joins, limit 10), which is `strokeBorder`'s definition, so BUG-91's inner
///   radius traces the picture exactly as the live rail does; the sheen is clipped to the un-inset
///   shape, as the live `.clipShape(shape)` is. The coverage mask comes from
///   `CardDepthStyle.coverageBand`, the live mask's own formula.
/// - Every number in the key is rounded (size to whole pixels; radius, width, alphas, coverage and
///   sheen ×100) and the bitmap is rendered FROM the key, never from the caller's raw values, so two
///   cards that share a key share an identical bitmap whichever of them asked first.
///
/// `nonisolated`: `NSCache` is thread-safe and the key, path and render helpers are pure, so they
/// are usable (and unit-testable) off the main actor. `CardDepthOverlay` calls in from its body.
nonisolated final class CardDepthRasterCache: @unchecked Sendable {
    static let shared = CardDepthRasterCache()

    /// Which of Card Depth's two layers a bitmap holds.
    nonisolated enum Layer: Hashable, Sendable {
        case rail
        case sheen
    }

    /// The shapes a bitmap can be keyed on. Every `nuvioCardDepth` call site passes one of these
    /// (the cards a `RoundedRectangle` with BUG-91's inner radius, Detail's cast avatar a `Circle`).
    /// Any other shape has no kind and `CardDepthOverlay` draws variant 1 for it.
    nonisolated enum ShapeKind: Hashable, Sendable {
        /// Corner size in pt ×100 (width, height) and whether the corners are `.continuous`.
        case roundedRect(cornerWidthX100: Int, cornerHeightX100: Int, continuous: Bool)
        case circle

        /// The kind of a call site's shape, or nil when the cache cannot draw it.
        init?<S: Shape>(_ shape: S) {
            if let rounded = shape as? RoundedRectangle {
                self = .roundedRect(cornerWidthX100: Key.x100(Double(rounded.cornerSize.width)),
                                    cornerHeightX100: Key.x100(Double(rounded.cornerSize.height)),
                                    continuous: rounded.style == .continuous)
            } else if shape is Circle {
                self = .circle
            } else {
                return nil
            }
        }
    }

    /// One bitmap's identity. The fields that do not apply to a layer are 0 (a sheen key carries no
    /// rail numbers, a rail key no sheen), so one sheen bitmap is shared across edge strengths and
    /// one rail bitmap across sheen strengths.
    nonisolated struct Key: Hashable, Sendable {
        var layer: Layer
        /// The bitmap's size in whole pixels (points × scale, rounded).
        var pixelWidth: Int
        var pixelHeight: Int
        /// The screen scale ×100 (1x = 100, 2x = 200).
        var scaleX100: Int
        /// The shape, with its inner radius (BUG-91) for a rounded rectangle.
        var shape: ShapeKind
        /// Rail: the stroke width (`CardDepthStyle.railWidth`) in pt ×100.
        var railWidthX100: Int
        /// Rail: the three gradient stops' alphas (`CardDepthStyle.railStops`) ×100.
        var topX100: Int
        var midX100: Int
        var bottomX100: Int
        /// Rail: Edge Coverage ×100; 100 (Full) draws no mask.
        var coverageX100: Int
        /// Sheen: the sheen's top alpha ×100.
        var sheenX100: Int

        static func x100(_ value: Double) -> Int { Int((value * 100).rounded()) }

        static func pixels(_ points: CGFloat, scale: CGFloat) -> Int { Int((points * scale).rounded()) }

        /// The rail bitmap for one card size and one resolved rail setting.
        static func rail(size: CGSize, scale: CGFloat, shape: ShapeKind, lineWidth: CGFloat,
                         stops: (top: Double, mid: Double, bottom: Double), coverage: Double) -> Key {
            Key(layer: .rail,
                pixelWidth: pixels(size.width, scale: scale),
                pixelHeight: pixels(size.height, scale: scale),
                scaleX100: x100(Double(scale)),
                shape: shape,
                railWidthX100: x100(Double(lineWidth)),
                topX100: x100(stops.top),
                midX100: x100(stops.mid),
                bottomX100: x100(stops.bottom),
                coverageX100: x100(min(max(coverage, 0), 1)),
                sheenX100: 0)
        }

        /// The sheen bitmap for one card size and one sheen strength.
        static func sheen(size: CGSize, scale: CGFloat, shape: ShapeKind, sheen: Double) -> Key {
            Key(layer: .sheen,
                pixelWidth: pixels(size.width, scale: scale),
                pixelHeight: pixels(size.height, scale: scale),
                scaleX100: x100(Double(scale)),
                shape: shape,
                railWidthX100: 0,
                topX100: 0,
                midX100: 0,
                bottomX100: 0,
                coverageX100: 0,
                sheenX100: x100(sheen))
        }
    }

    /// `NSCache` keys must be objects.
    nonisolated private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private let cache = NSCache<KeyBox, UIImage>()

    /// A poster rail at 2x is about 0.4 MB; a typical Home holds a handful of keys (one per card
    /// family and size, two layers each). The limits only bound a pathological spread of sizes.
    init(countLimit: Int = 64, totalCostLimit: Int = 48 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// The bitmap for `key`, rendered on the first ask and shared afterwards; nil for an empty size.
    func image(for key: Key) -> UIImage? {
        let box = KeyBox(key)
        if let hit = cache.object(forKey: box) { return hit }
        guard let image = Self.render(key) else { return nil }
        cache.setObject(image, forKey: box, cost: key.pixelWidth * key.pixelHeight * 4)
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    // MARK: - Rendering (pure: everything comes from the key)

    /// Renders `key`'s bitmap: 8-bit sRGB, transparent, at the keyed scale and pixel size.
    static func render(_ key: Key) -> UIImage? {
        guard key.pixelWidth > 0, key.pixelHeight > 0, key.scaleX100 > 0 else { return nil }
        let scale = CGFloat(key.scaleX100) / 100
        let size = CGSize(width: CGFloat(key.pixelWidth) / scale, height: CGFloat(key.pixelHeight) / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            switch key.layer {
            case .rail: drawRail(key, size: size, in: context.cgContext)
            case .sheen: drawSheen(key, size: size, in: context.cgContext)
            }
        }
    }

    /// `kind`'s path in `rect`, inset by `inset` the way `InsettableShape.inset(by:)` insets it
    /// (`strokeBorder` strokes the shape inset by half its line width).
    static func shapePath(_ kind: ShapeKind, in rect: CGRect, inset: CGFloat) -> Path {
        switch kind {
        case let .roundedRect(cornerWidthX100, cornerHeightX100, continuous):
            let corner = CGSize(width: CGFloat(cornerWidthX100) / 100, height: CGFloat(cornerHeightX100) / 100)
            return RoundedRectangle(cornerSize: corner, style: continuous ? .continuous : .circular)
                .inset(by: inset)
                .path(in: rect)
        case .circle:
            return Circle().inset(by: inset).path(in: rect)
        }
    }

    /// The live rail: `shape.strokeBorder(LinearGradient(white @ top / mid / bottom, .top → .bottom),
    /// lineWidth:)`, then `.mask(coverageMask)` below Full.
    private static func drawRail(_ key: Key, size: CGSize, in cg: CGContext) {
        let lineWidth = CGFloat(key.railWidthX100) / 100
        guard lineWidth > 0 else { return }
        let rect = CGRect(origin: .zero, size: size)
        cg.saveGState()
        cg.addPath(shapePath(key.shape, in: rect, inset: lineWidth / 2).cgPath)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.butt)
        cg.setLineJoin(.miter)
        cg.setMiterLimit(10)
        cg.replacePathWithStrokedPath()
        cg.clip()
        drawVerticalWhiteGradient(in: cg, height: size.height, stops: [
            (alpha(key.topX100), 0), (alpha(key.midX100), 0.5), (alpha(key.bottomX100), 1),
        ])
        cg.restoreGState()

        let coverage = Double(key.coverageX100) / 100
        guard coverage < 1 else { return }
        // The coverage mask: keep the rail's alpha × the mask's (destination-in).
        let band = CardDepthStyle.coverageBand(coverage: coverage)
        cg.saveGState()
        cg.setBlendMode(.destinationIn)
        drawVerticalWhiteGradient(in: cg, height: size.height, stops: [
            (1, 0), (1, band.fadeStart), (0, band.fadeEnd), (0, 1),
        ])
        cg.restoreGState()
    }

    /// The live sheen: `LinearGradient(white @ sheen → clear @ 22 % → clear, .top → .bottom)`
    /// clipped to the shape.
    private static func drawSheen(_ key: Key, size: CGSize, in cg: CGContext) {
        let sheen = alpha(key.sheenX100)
        guard sheen > 0 else { return }
        let rect = CGRect(origin: .zero, size: size)
        cg.saveGState()
        cg.addPath(shapePath(key.shape, in: rect, inset: 0).cgPath)
        cg.clip()
        drawVerticalWhiteGradient(in: cg, height: size.height, stops: [
            (sheen, 0), (0, CardDepthStyle.sheenFadeLocation), (0, 1),
        ])
        cg.restoreGState()
    }

    /// A top-to-bottom gradient of white at the given alphas, filling the current clip. Only the
    /// alpha varies, so straight and premultiplied interpolation agree (white → clear in SwiftUI is
    /// white at a falling alpha, never a grey).
    private static func drawVerticalWhiteGradient(in cg: CGContext, height: CGFloat,
                                                  stops: [(alpha: Double, location: Double)]) {
        var components: [CGFloat] = []
        var locations: [CGFloat] = []
        for stop in stops {
            components += [1, 1, 1, CGFloat(stop.alpha)]
            locations.append(CGFloat(stop.location))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorSpace: space, colorComponents: components,
                                        locations: locations, count: stops.count) else { return }
        cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func alpha(_ x100: Int) -> Double { min(max(Double(x100) / 100, 0), 1) }
}
