import XCTest
@testable import NuvioTV

/// W2-5 (c): the rig's Home A/B knob resolves off by default and on for a `YES` launch value.
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
    }
}
