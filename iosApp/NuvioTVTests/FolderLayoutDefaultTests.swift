import XCTest
@testable import NuvioTV

/// Home Stage & Strip (H5, W2-B; P2 spec §2.1) + FEAT-71 (Batch B): which page a folder opens as.
/// Settings › Home Screen › Collections Layout is the only Stage-side source since review r1 P2-1
/// (the rc3/rc4 per-folder Grid store is no longer read).
final class FolderLayoutDefaultTests: XCTestCase {

    // MARK: - FolderPageLayout

    func testClassicIsAlwaysTheGrid() {
        for defaultGrid in [false, true] {
            XCTAssertEqual(FolderPageLayout.resolve(homeLayout: .classic, defaultGrid: defaultGrid), .grid)
        }
    }

    func testStageFollowsTheSettingsDefault() {
        XCTAssertEqual(FolderPageLayout.resolve(homeLayout: .stage, defaultGrid: false), .rows)
        XCTAssertEqual(FolderPageLayout.resolve(homeLayout: .stage, defaultGrid: true), .grid)
    }

    func testFolderLayoutDefaultKeyAndResolve() {
        XCTAssertEqual(FolderLayoutDefault.defaultsKey, "folder_layout_default")
        XCTAssertEqual(FolderLayoutDefault.defaultValue, .rows)
        XCTAssertEqual(FolderLayoutDefault.resolve(nil), .rows)
        XCTAssertEqual(FolderLayoutDefault.resolve(""), .rows)
        XCTAssertEqual(FolderLayoutDefault.resolve("bogus"), .rows)
        XCTAssertEqual(FolderLayoutDefault.resolve("grid"), .grid)
        XCTAssertEqual(FolderLayoutDefault.resolve(" Grid "), .grid)
        XCTAssertEqual(FolderLayoutDefault.resolve("rows"), .rows)
        XCTAssertTrue(FolderLayoutDefault.grid.isGrid)
        XCTAssertFalse(FolderLayoutDefault.rows.isGrid)
    }
}
