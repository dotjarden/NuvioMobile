import XCTest
import SharedCore
@testable import NuvioTV

/// Direction C D9: the Settings > Sources "Source List Opens With" row. The default is Best Pick; the
/// view model reads it until the shared repository has emitted, and the row's explainer names it.
@MainActor
final class SourceListOpensWithSettingTests: XCTestCase {
    func testViewModelReadsBestPickBeforeTheRepositoryEmits() {
        let vm = BadgeSettingsViewModel()
        XCTAssertEqual(vm.listOpensWith, StreamListOpensWith.bestPick)
    }

    func testDescriptionCopyNamesBothOptionsAndTheDefault() {
        let copy = String(localized: SettingsDescriptions.text(for: .sourcesOpensWith))
        XCTAssertTrue(copy.hasPrefix("Best Pick "), copy)
        XCTAssertTrue(copy.contains("Full List "), copy)
        XCTAssertTrue(copy.hasSuffix("Default: Best Pick."), copy)
    }
}
