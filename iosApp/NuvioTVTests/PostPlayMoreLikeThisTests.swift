import XCTest
import SharedCore
@testable import NuvioTV

final class PostPlayMoreLikeThisTests: XCTestCase {
    private func preview(_ id: String) -> MetaPreview {
        MetaPreview(
            id: id, type: "movie", name: id, poster: nil, banner: nil, logo: nil,
            posterShape: PosterShape.poster, description: nil, releaseInfo: nil, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: nil, genres: [], rawPosterUrl: nil,
            landscapePoster: nil, rawLandscapePosterUrl: nil, customPosterApplied: false
        )
    }

    func testFilterDropsCurrentTitle() {
        let out = PostPlayMoreLikeThis.filter(["a", "me", "b"].map(preview), excludingId: "me")
        XCTAssertEqual(out.map(\.id), ["a", "b"])
    }

    func testFilterCapsAtTwelve() {
        let items = (1...20).map { preview("t\($0)") }
        let out = PostPlayMoreLikeThis.filter(items, excludingId: "me")
        XCTAssertEqual(out.count, 12)
        XCTAssertEqual(out.last?.id, "t12")
    }

    func testFilterKeepsOrder() {
        let out = PostPlayMoreLikeThis.filter(["z", "a", "m"].map(preview), excludingId: "me")
        XCTAssertEqual(out.map(\.id), ["z", "a", "m"])
    }

    func testFilterDropsDuplicateIds() {
        let out = PostPlayMoreLikeThis.filter(["a", "b", "a", "b", "c"].map(preview), excludingId: "me")
        XCTAssertEqual(out.map(\.id), ["a", "b", "c"])
    }
}
