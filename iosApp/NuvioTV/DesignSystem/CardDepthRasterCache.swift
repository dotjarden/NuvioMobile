import SwiftUI
import UIKit

/// W3-13 (UX-16 / BUG-153 remainder), the Card Depth rendering picked by the `-debug.cardDepthRender`
/// A/B on the Apple TV (the knob is gone; parked by BUG-221, revived 2026-10-23 without its
/// `GeometryReader`): the two gradient layers as bitmaps,
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
/// are usable (and unit-testable) off the main actor. `CardDepthBitmapLayers` calls in from its
/// body, with a size it learned after layout (BUG-221: never from inside a `GeometryReader`).
nonisolated final class CardDepthRasterCache: @unchecked Sendable {
    static let shared = CardDepthRasterCache()

    /// Which of Card Depth's two layers a bitmap holds.
    nonisolated enum Layer: Hashable, Sendable {
        case rail
        case sheen
    }

    /// The shapes a bitmap can be keyed on. Every `nuvioCardDepth` call site passes one of these
    /// (the cards a `RoundedRectangle` with BUG-91's inner radius, Detail's cast avatar a `Circle`).
    /// Any other shape has no kind and `CardDepthOverlay` draws the live layers for it.
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

        /// A bitmap with at least one pixel each way at a real scale; `render` returns nil otherwise.
        var isDrawable: Bool { pixelWidth > 0 && pixelHeight > 0 && scaleX100 > 0 }

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

    /// BUG-221: the two keys one `CardDepthBitmapLayers` draws, nil for a layer with nothing to
    /// draw (no size yet, a zero strength, a zero rail width), which then shows `placeholder`.
    nonisolated struct LayerKeys: Equatable, Sendable {
        var sheen: Key?
        var rail: Key?

        init(size: CGSize, scale: CGFloat, shape: ShapeKind, sheen: Double, edge: Double, lineWidth: CGFloat,
             stops: (top: Double, mid: Double, bottom: Double), coverage: Double) {
            let sheenKey = Key.sheen(size: size, scale: scale, shape: shape, sheen: sheen)
            let railKey = Key.rail(size: size, scale: scale, shape: shape, lineWidth: lineWidth,
                                   stops: stops, coverage: coverage)
            self.sheen = sheenKey.isDrawable && sheenKey.sheenX100 > 0 ? sheenKey : nil
            self.rail = railKey.isDrawable && edge > 0 && railKey.railWidthX100 > 0 ? railKey : nil
        }
    }

    /// A fully transparent 1 × 1 bitmap: what a layer shows while it has no key. `.resizable()`
    /// stretches it to the card, so the layer keeps its slot and draws nothing.
    static let placeholder: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
    }()

    /// `NSCache` keys must be objects.
    nonisolated private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private let cache = NSCache<KeyBox, UIImage>()

    /// One bitmap costs its pixels × 4 bytes: a 220 × 330 pt poster at 2x is 440 × 660 px ≈ 1.16 MB,
    /// an episode / landscape tile ≈ 1.6 MB, and each card size holds two (rail + sheen). A typical
    /// Home (a few card families and sizes) holds about 10-15 MB. The 64-entry / 48 MB bounds cover
    /// that with room for Detail's sizes; past them `NSCache` evicts and the next ask re-renders.
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

    /// BUG-221: never nil, so the layer's `Image` is always there: the bitmap for `key`, or
    /// `placeholder` for no key and for a key that renders nothing.
    func layerImage(for key: Key?) -> UIImage {
        guard let key else { return Self.placeholder }
        return image(for: key) ?? Self.placeholder
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
