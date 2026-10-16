import XCTest
import SharedCore
@testable import NuvioTV

/// B1 (BUG-145 + BUG-159 revert + FEAT-67; Steven, beta.19-rc4 verdict 2026-10-16): Show Catalog
/// Details in Headings. Off by default; off, a collection folder's preview carries no
/// "name · N sources" line (both Homes and the folder page), and every other field is unchanged.
@MainActor
final class HeadingDetailsSettingTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let name = "HeadingDetailsSettingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func folder(backdrop: String? = "https://example.com/b.jpg") -> CollectionFolder {
        CollectionFolder(id: "f1", title: " Aventure ", coverImageUrl: nil, focusGifUrl: nil,
                         focusGifEnabled: true, mobileFocusGifEnabled: true, coverEmoji: nil,
                         tileShape: "poster", hideTitle: false, sources: [], catalogSources: [],
                         heroBackdropUrl: backdrop, heroVideoUrl: nil, titleLogoUrl: nil)
    }

    private func collection(_ folder: CollectionFolder) -> NuvioCollection {
        NuvioCollection(id: "c1", title: "Genres", backdropImageUrl: nil, pinToTop: false,
                        viewMode: "TABBED_GRID", showAllTab: true, folders: [folder])
    }

    func testDefaultIsOff() {
        XCTAssertFalse(HeadingDetailsSetting.defaultValue)
        XCTAssertEqual(HeadingDetailsSetting.defaultsKey, "show_catalog_details_in_headings")
        let store = defaults()
        XCTAssertFalse(HeadingDetailsSetting.current(store))
        store.set(true, forKey: HeadingDetailsSetting.defaultsKey)
        XCTAssertTrue(HeadingDetailsSetting.current(store))
    }

    func testFolderPreviewWithoutDetailsDropsOnlyTheLine() throws {
        let f = folder()
        let c = collection(f)
        let on = try XCTUnwrap(HomeRowPreviews.folder(collection: c, folder: f, showsDetails: true))
        let off = try XCTUnwrap(HomeRowPreviews.folder(collection: c, folder: f, showsDetails: false))
        XCTAssertEqual(on.description_, HomeView.folderHeroDescription(collection: c, folder: f))
        XCTAssertNil(off.description_)
        XCTAssertEqual(off.id, on.id)
        XCTAssertEqual(off.type, on.type)
        XCTAssertEqual(off.name, "Aventure")
        XCTAssertEqual(off.name, on.name)
        XCTAssertEqual(off.releaseInfo, "Genres")
        XCTAssertEqual(off.releaseInfo, on.releaseInfo)
        XCTAssertEqual(off.banner, on.banner)
    }

    func testPlainFolderPreviewWithoutDetailsDropsOnlyTheLine() {
        let f = folder(backdrop: nil)
        let c = collection(f)
        XCTAssertNil(HomeRowPreviews.folder(collection: c, folder: f, showsDetails: false),
                     "a folder with neither a backdrop nor a logo has no Home preview")
        let on = FolderRowsPlan.plainFolderPreview(collection: c, folder: f, showsDetails: true)
        let off = FolderRowsPlan.plainFolderPreview(collection: c, folder: f, showsDetails: false)
        XCTAssertNotNil(on.description_)
        XCTAssertNil(off.description_)
        XCTAssertEqual(off.id, on.id)
        XCTAssertEqual(off.type, on.type)
        XCTAssertEqual(off.name, on.name)
        XCTAssertEqual(off.releaseInfo, on.releaseInfo)
    }
}
