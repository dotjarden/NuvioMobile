import XCTest
import SharedCore
@testable import NuvioTV

/// D-7 (design review 2026-10-22): the folder line repeats the folder's name only when the hero
/// cannot show it any other way (a wordmark bitmap); a text-wordmark folder gets the count alone.
@MainActor
final class FolderHeroDescriptionTests: XCTestCase {
    private func folder(logo: String?, sources: Int) -> CollectionFolder {
        let list = (0..<sources).map { i in
            CollectionSource(provider: "addon", addonId: "a\(i)", type: "movie", catalogId: "c\(i)", genre: nil,
                             tmdbSourceType: nil, title: nil, tmdbId: nil, traktListId: nil, mediaType: nil,
                             sortBy: nil, sortHow: nil, filters: nil)
        }
        return CollectionFolder(id: "f1", title: " Test Folder ", coverImageUrl: nil, focusGifUrl: nil,
                                focusGifEnabled: true, mobileFocusGifEnabled: true, coverEmoji: nil,
                                tileShape: "poster", hideTitle: false, sources: list, catalogSources: [],
                                heroBackdropUrl: "https://example.com/b.jpg", heroVideoUrl: nil, titleLogoUrl: logo)
    }

    private func collection(_ folder: CollectionFolder) -> NuvioCollection {
        NuvioCollection(id: "c1", title: "Test Collection", backdropImageUrl: nil, pinToTop: false,
                        viewMode: "TABBED_GRID", showAllTab: true, folders: [folder])
    }

    func testTextWordmarkFolderCarriesTheCountAlone() {
        let f = folder(logo: nil, sources: 2)
        XCTAssertEqual(HomeView.folderHeroDescription(collection: collection(f), folder: f), "2 sources")
    }

    func testBitmapWordmarkFolderKeepsItsName() {
        let f = folder(logo: "https://example.com/logo.png", sources: 2)
        XCTAssertEqual(HomeView.folderHeroDescription(collection: collection(f), folder: f), "Test Folder \u{00B7} 2 sources")
    }

    func testNoSourcesReadsCollectionFolder() {
        let f = folder(logo: nil, sources: 0)
        XCTAssertEqual(HomeView.folderHeroDescription(collection: collection(f), folder: f), "Collection folder")
    }
}
