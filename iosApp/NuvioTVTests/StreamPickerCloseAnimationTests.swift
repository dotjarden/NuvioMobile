import UIKit
import XCTest
@testable import NuvioTV

/// BUG-185: the UIKit fallback for an instant player-cover close turns UIKit animations off from
/// the cover binding's setter until `onDismiss`, and a 1 s watchdog turns them back on when the
/// dismiss never reports, so the app can never be left unanimated.
@MainActor
final class StreamPickerCloseAnimationTests: XCTestCase {
    override func tearDown() async throws {
        StreamPickerCloseAnimation.resumeUIKitAnimations()
        UIView.setAnimationsEnabled(true)
        try await super.tearDown()
    }

    func testSuspendThenResume() {
        StreamPickerCloseAnimation.suspendUIKitAnimations()
        XCTAssertFalse(UIView.areAnimationsEnabled)
        StreamPickerCloseAnimation.resumeUIKitAnimations()
        XCTAssertTrue(UIView.areAnimationsEnabled)
    }

    func testResumeWithoutSuspendLeavesAnimationsAlone() {
        UIView.setAnimationsEnabled(true)
        StreamPickerCloseAnimation.resumeUIKitAnimations()
        XCTAssertTrue(UIView.areAnimationsEnabled)
    }

    func testWatchdogReenablesAfterOneSecond() async throws {
        StreamPickerCloseAnimation.suspendUIKitAnimations()
        XCTAssertFalse(UIView.areAnimationsEnabled)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertTrue(UIView.areAnimationsEnabled, "the watchdog must re-enable UIKit animations")
    }

    func testFallbackIsOffByDefault() {
        let key = "debug.pickerCloseUIKitNoAnim"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(StreamPickerCloseAnimation.uiKitFallback)
    }
}
