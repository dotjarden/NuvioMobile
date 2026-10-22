import XCTest
@testable import NuvioTV

/// W2-5 (c) / W3-13: the rig's Home A/B knobs resolve off by default and on for a launch value.
final class HomePerfKnobsTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HomePerfKnobsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let keys = [HomePerfKnobs.noCardDepthKey]

    func testKeysAreTheDocumentedLaunchArguments() {
        XCTAssertEqual(keys, ["debug.homeNoCardDepth"])
        XCTAssertEqual(HomePerfKnobs.cardDepthRenderKey, "debug.cardDepthRender")
    }

    func testDefaultIsOff() {
        for key in keys {
            XCTAssertFalse(HomePerfKnobs.resolve(key, defaults: defaults), key)
        }
    }

    func testYesStringFromALaunchArgumentIsOn() {
        // `-key YES` lands in the argument domain as the string "YES".
        for key in keys {
            defaults.set("YES", forKey: key)
            XCTAssertTrue(HomePerfKnobs.resolve(key, defaults: defaults), key)
        }
    }

    func testNoAndBoolFalseAreOff() {
        for key in keys {
            defaults.set("NO", forKey: key)
            XCTAssertFalse(HomePerfKnobs.resolve(key, defaults: defaults), key)
            defaults.set(false, forKey: key)
            XCTAssertFalse(HomePerfKnobs.resolve(key, defaults: defaults), key)
        }
    }

    func testKnobIsReadFromTheGivenDefaultsOnly() {
        // Setting the key in one suite does not leak into another, and a YES launch argument parses.
        defaults.set("YES", forKey: HomePerfKnobs.noCardDepthKey)
        XCTAssertTrue(HomePerfKnobs.resolve(HomePerfKnobs.noCardDepthKey, defaults: defaults))
        let other = UserDefaults(suiteName: suiteName + ".other")!
        defer { other.removePersistentDomain(forName: suiteName + ".other") }
        XCTAssertFalse(HomePerfKnobs.resolve(HomePerfKnobs.noCardDepthKey, defaults: other))
    }

    func testTheSimulatorRunHasNoKnobSet() {
        // The unit-test host launches without the knobs, so the latched values are the defaults.
        XCTAssertFalse(HomePerfKnobs.noCardDepth)
        XCTAssertEqual(HomePerfKnobs.cardDepthRender, .live)
    }

    // MARK: - W3-13: -debug.cardDepthRender 0|1|2

    private func render() -> HomePerfKnobs.CardDepthRender {
        HomePerfKnobs.resolveCardDepthRender(HomePerfKnobs.cardDepthRenderKey, defaults: defaults)
    }

    func testRenderVariantsAreZeroOneTwo() {
        XCTAssertEqual(HomePerfKnobs.CardDepthRender.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(HomePerfKnobs.CardDepthRender.allCases, [.live, .drawingGroup, .rasterCache])
    }

    func testRenderDefaultsToTheLiveLayers() {
        XCTAssertEqual(render(), .live)
    }

    func testRenderLaunchStringsSelectEachVariant() {
        // `-debug.cardDepthRender 2` lands in the argument domain as the string "2".
        for (raw, expected) in [("0", HomePerfKnobs.CardDepthRender.live), ("1", .drawingGroup), ("2", .rasterCache)] {
            defaults.set(raw, forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(render(), expected, raw)
        }
    }

    func testRenderIntegersSelectEachVariant() {
        for variant in HomePerfKnobs.CardDepthRender.allCases {
            defaults.set(variant.rawValue, forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(render(), variant)
        }
    }

    func testRenderOutOfRangeOrGarbageIsTheLiveLayers() {
        for raw in ["3", "-1", "99", "YES", "fast", ""] {
            defaults.set(raw, forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(render(), .live, "'\(raw)'")
        }
    }

    // MARK: - Review r1 P3-4 / r2 P3-2: the knob's launch line

    private func logLine() -> String? {
        HomePerfKnobs.cardDepthRenderLogLine(HomePerfKnobs.cardDepthRenderKey, defaults: defaults)
    }

    func testLogLineIsAbsentWhenTheKnobIsNotPassed() {
        XCTAssertNil(logLine())
    }

    /// Any clean variant logs, 0 included, so a walk at 0 proves which variant it measured.
    func testLogLineNamesTheVariantAndHasNoFlagWhenTheValueIsClean() {
        for variant in HomePerfKnobs.CardDepthRender.allCases {
            defaults.set(String(variant.rawValue), forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(logLine(), "[HomePerfKnobs] cardDepthRender=\(variant.rawValue)", "string \(variant.rawValue)")
            // `defaults write -int` lands as an NSNumber.
            defaults.set(variant.rawValue, forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(logLine(), "[HomePerfKnobs] cardDepthRender=\(variant.rawValue)", "int \(variant.rawValue)")
        }
    }

    /// A mistyped value no longer reads like a clean 0: the line carries the variant actually
    /// resolved and the raw text.
    func testLogLineFlagsAnUnparsedValueWithTheVariantItResolved() {
        // `UserDefaults.integer(forKey:)` reads a string whole: "2.5" and "abc2" are not integers, so
        // the knob falls back to the live layers, and the line says so.
        let cases: [(raw: String, resolved: Int)] = [
            ("YES", 0), ("garbage", 0), ("5", 0), ("-1", 0), ("2.5", 0), ("abc2", 0),
        ]
        for (raw, resolved) in cases {
            defaults.set(raw, forKey: HomePerfKnobs.cardDepthRenderKey)
            XCTAssertEqual(logLine(), "[HomePerfKnobs] cardDepthRender=\(resolved) (unparsed value \"\(raw)\")", raw)
        }
        // A number is truncated by `integer(forKey:)`, so a double 2.5 resolves to variant 2 but is
        // not exactly variant 2.
        defaults.set(2.5, forKey: HomePerfKnobs.cardDepthRenderKey)
        XCTAssertEqual(logLine(), "[HomePerfKnobs] cardDepthRender=2 (unparsed value \"2.5\")")
    }

    /// A padded value is not accepted by the knob (`integer(forKey:)` reads the string whole, so
    /// `" 2 "` is not 2): the walk gets the live layers and the line says so, quoting the value
    /// trimmed.
    func testLogLineFlagsAPaddedValueTheKnobDidNotTake() {
        defaults.set(" 2 ", forKey: HomePerfKnobs.cardDepthRenderKey)
        XCTAssertEqual(render(), .live)
        XCTAssertEqual(logLine(), "[HomePerfKnobs] cardDepthRender=0 (unparsed value \"2\")")
    }
}
