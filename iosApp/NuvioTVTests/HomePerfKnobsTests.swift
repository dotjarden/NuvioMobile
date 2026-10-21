import XCTest
@testable import NuvioTV

/// W2-5 (c): the rig's three Home A/B knobs resolve off by default and on for a `YES` launch value.
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

    private let keys = [HomePerfKnobs.noStripEdgeMaskKey, HomePerfKnobs.noPageOpacityKey, HomePerfKnobs.noCardDepthKey]

    func testKeysAreTheDocumentedLaunchArguments() {
        XCTAssertEqual(keys, ["debug.homeNoStripEdgeMask", "debug.homeNoPageOpacity", "debug.homeNoCardDepth"])
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

    func testKnobsAreIndependent() {
        defaults.set(true, forKey: HomePerfKnobs.noPageOpacityKey)
        XCTAssertFalse(HomePerfKnobs.resolve(HomePerfKnobs.noStripEdgeMaskKey, defaults: defaults))
        XCTAssertTrue(HomePerfKnobs.resolve(HomePerfKnobs.noPageOpacityKey, defaults: defaults))
        XCTAssertFalse(HomePerfKnobs.resolve(HomePerfKnobs.noCardDepthKey, defaults: defaults))
    }

    func testTheSimulatorRunHasNoKnobSet() {
        // The unit-test host launches without the knobs, so the latched values are the defaults.
        XCTAssertFalse(HomePerfKnobs.noStripEdgeMask)
        XCTAssertFalse(HomePerfKnobs.noPageOpacity)
        XCTAssertFalse(HomePerfKnobs.noCardDepth)
    }
}
