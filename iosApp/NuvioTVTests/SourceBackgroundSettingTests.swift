import XCTest
import SharedCore
@testable import NuvioTV

/// Stream picker A, P4.1: the Settings > Sources "Source Background" row. The tvOS default is
/// Cinematic (decision D1); the view model reads the platform default until the shared repository
/// has emitted, and the row's explainer names that default.
@MainActor
final class SourceBackgroundSettingTests: XCTestCase {
    func testTvOsDefaultIsCinematic() {
        XCTAssertEqual(StreamBackgroundDefaults.shared.platformDefault, StreamBackgroundMode.cinematic)
    }

    func testViewModelReadsCinematicBeforeTheRepositoryEmits() {
        // Review r1: pins decision D1 at the view-model level, not just "state is nil".
        let vm = BadgeSettingsViewModel()
        XCTAssertEqual(vm.backgroundMode, StreamBackgroundMode.cinematic)
    }

    func testDescriptionCopyNamesBothOptionsAndTheDefault() {
        let copy = String(localized: SettingsDescriptions.text(for: .sourcesBackground))
        XCTAssertTrue(copy.hasPrefix("Cinematic "), copy)
        XCTAssertTrue(copy.contains("Normal "), copy)
        XCTAssertTrue(copy.hasSuffix("Default: Cinematic."), copy)
    }
}
