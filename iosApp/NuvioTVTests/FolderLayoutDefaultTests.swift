import XCTest
@testable import NuvioTV

/// Home Stage & Strip (H5, W2-B; P2 spec §2.1) + FEAT-71 (Batch B): which page a folder opens as.
/// Settings › Home Screen › Collections Layout is the only Stage-side source since review r1 P2-1
/// (the rc3/rc4 per-folder Grid store is no longer read).
final class FolderLayoutDefaultTests: XCTestCase {

    // MARK: - FolderPageLayout

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

    // MARK: - Batch F: per-layout defaults + FEAT-76 per-folder override

    func testOverrideWinsOverTheDefault() {
        XCTAssertEqual(FolderPageLayout.resolve(override: .rows, defaultForLayout: .grid), .rows)
        XCTAssertEqual(FolderPageLayout.resolve(override: .grid, defaultForLayout: .rows), .grid)
        XCTAssertEqual(FolderPageLayout.resolve(override: .followDefault, defaultForLayout: .grid), .grid)
        XCTAssertEqual(FolderPageLayout.resolve(override: .followDefault, defaultForLayout: .rows), .rows)
    }

    func testEachLayoutKeepsItsOwnDefault() {
        let defaults = UserDefaults(suiteName: "FolderLayoutDefaultTests.\(UUID().uuidString)")!
        XCTAssertEqual(FolderLayoutDefault.current(for: .classic, defaults: defaults), .grid, "Classic opens as before")
        XCTAssertEqual(FolderLayoutDefault.current(for: .stage, defaults: defaults), .rows)
        defaults.set("rows", forKey: FolderLayoutDefault.defaultsKey(for: .classic))
        XCTAssertEqual(FolderLayoutDefault.current(for: .classic, defaults: defaults), .rows)
        XCTAssertEqual(FolderLayoutDefault.current(for: .stage, defaults: defaults), .rows)
        defaults.set("bogus", forKey: FolderLayoutDefault.defaultsKey(for: .classic))
        XCTAssertEqual(FolderLayoutDefault.current(for: .classic, defaults: defaults), .grid)
    }

    func testOverrideStoreRoundTripsAndDefaultRemovesTheKey() {
        let defaults = UserDefaults(suiteName: "FolderLayoutDefaultTests.\(UUID().uuidString)")!
        XCTAssertEqual(FolderLayoutOverride.current(collectionId: "c", folderId: "f", defaults: defaults), .followDefault)
        FolderLayoutOverride.set(.grid, collectionId: "c", folderId: "f", defaults: defaults)
        XCTAssertEqual(FolderLayoutOverride.current(collectionId: "c", folderId: "f", defaults: defaults), .grid)
        XCTAssertEqual(FolderLayoutOverride.current(collectionId: "c", folderId: "g", defaults: defaults), .followDefault,
                       "keyed per folder")
        FolderLayoutOverride.set(.followDefault, collectionId: "c", folderId: "f", defaults: defaults)
        XCTAssertNil(defaults.object(forKey: FolderLayoutOverride.key(collectionId: "c", folderId: "f")))
    }
}
