import XCTest
import SharedCore
@testable import NuvioTV

/// Polish D5: the Settings > Sources "Group Sources By" row. The default is Quality; the view model
/// reads it until the shared repository has emitted, and the row's explainer names that default.
@MainActor
final class SourceGroupingSettingTests: XCTestCase {
    func testViewModelReadsQualityBeforeTheRepositoryEmits() {
        let vm = BadgeSettingsViewModel()
        XCTAssertEqual(vm.groupingMode, StreamGroupingMode.quality)
    }

    func testDescriptionCopyNamesBothOptionsAndTheDefault() {
        let copy = String(localized: SettingsDescriptions.text(for: .sourcesGrouping))
        XCTAssertTrue(copy.hasPrefix("Quality "), copy)
        XCTAssertTrue(copy.contains("Add-on "), copy)
        XCTAssertTrue(copy.hasSuffix("Default: Quality."), copy)
    }
}
