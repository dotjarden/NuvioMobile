import XCTest
@testable import NuvioTV

/// FEAT-65 (Steven, beta.19-rc3 follow-up 2026-10-08): "Open Last Profile at Launch". The rule is
/// upstream's `rememberedStartupProfile` (composeApp `App.kt`) plus tvOS's once-per-process latch.
final class ProfileAutoEnterTests: XCTestCase {

    private func decide(enabled: Bool = true,
                        everSelected: Bool = true,
                        exists: Bool = true,
                        pin: Bool = false,
                        fired: Bool = false) -> Bool {
        ProfileAutoEnter.decision(enabled: enabled, everSelected: everSelected, activeProfileExists: exists,
                                  pinEnabled: pin, alreadyFiredThisLaunch: fired)
    }

    func testEntersTheRememberedProfileWhenEveryTermHolds() {
        XCTAssertTrue(decide())
    }

    func testOffByDefaultMeansThePicker() {
        XCTAssertFalse(decide(enabled: false))
    }

    func testNeverSelectedBeforeMeansThePicker() {
        XCTAssertFalse(decide(everSelected: false))
    }

    func testAMissingStoredProfileMeansThePicker() {
        XCTAssertFalse(decide(exists: false))
    }

    func testAPinProfileAlwaysShowsThePicker() {
        XCTAssertFalse(decide(pin: true), "the picker asks for the PIN; auto-enter must never bypass it")
    }

    func testFiresAtMostOncePerProcess() {
        XCTAssertFalse(decide(fired: true), "Switch Profile and sign-out → sign-in must show the picker")
    }

    /// The whole table: true for exactly one combination.
    func testExactlyOneCombinationEnters() {
        var hits = 0
        for enabled in [false, true] {
            for ever in [false, true] {
                for exists in [false, true] {
                    for pin in [false, true] {
                        for fired in [false, true] where decide(enabled: enabled, everSelected: ever, exists: exists,
                                                                pin: pin, fired: fired) {
                            hits += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(hits, 1)
    }

    func testDebugKeyName() {
        XCTAssertEqual(ProfileAutoEnter.debugKey, "debug.rememberLastProfile")
    }

    func testDebugOverrideReadsOnlyWhenPresent() throws {
        let suite = "ProfileAutoEnterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(ProfileAutoEnter.debugEnabledOverride(defaults), "absent: the stored flag decides")
        defaults.set(true, forKey: ProfileAutoEnter.debugKey)
        #if DEBUG
        XCTAssertEqual(ProfileAutoEnter.debugEnabledOverride(defaults), true)
        defaults.set(false, forKey: ProfileAutoEnter.debugKey)
        XCTAssertEqual(ProfileAutoEnter.debugEnabledOverride(defaults), false)
        #else
        XCTAssertNil(ProfileAutoEnter.debugEnabledOverride(defaults))
        #endif
    }
}
