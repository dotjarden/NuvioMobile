import AVFoundation
import CoreMedia
import SharedCore
import XCTest
@testable import NuvioTV

/// P4 (A8): the native item's `externalMetadata` (system bar title/subtitle, Info synopsis, artwork).
final class NativeNowPlayingMetadataTests: XCTestCase {
    private func context(series: Bool, synopsis: String?) -> PlaybackContext {
        var ctx = PlaybackContext(
            url: URL(string: "https://cdn.example.com/a.mkv")!, title: "Show", contentType: series ? "series" : "movie",
            parentMetaId: "tt1", videoId: series ? "tt1:1:4" : "tt1",
            season: series ? 1 : nil, episode: series ? 4 : nil, poster: "https://img.example.com/p.jpg",
            background: nil, providerName: nil, providerAddonId: nil,
            streamTitle: "Release.1080p", streamSubtitle: nil, externalSubtitles: []
        )
        ctx.synopsis = synopsis
        if series {
            ctx.episodes = [MetaVideo(id: "tt1:1:4", title: "Name", released: nil, available: true, thumbnail: nil,
                                      seasonPoster: nil, season: KotlinInt(int: 1), episode: KotlinInt(int: 4),
                                      overview: nil, runtime: nil, rating: nil, streams: [])]
        }
        return ctx
    }

    private func value(_ items: [AVMetadataItem], _ id: AVMetadataIdentifier) -> String? {
        items.first { $0.identifier == id }?.value as? String
    }

    func testSeriesItems() {
        let items = NativeNowPlayingMetadata.textItems(context: context(series: true, synopsis: "Plot"))
        XCTAssertEqual(value(items, .commonIdentifierTitle), "Show")
        XCTAssertEqual(value(items, .iTunesMetadataTrackSubTitle), "S1 · E4 · Name")
        XCTAssertEqual(value(items, .commonIdentifierDescription), "Plot")
        XCTAssertTrue(items.allSatisfy { $0.extendedLanguageTag == "und" })
    }

    func testMovieUsesStreamLabelAndOmitsMissingSynopsis() {
        let items = NativeNowPlayingMetadata.textItems(context: context(series: false, synopsis: nil))
        XCTAssertEqual(value(items, .iTunesMetadataTrackSubTitle), "Release.1080p")
        XCTAssertNil(items.first { $0.identifier == .commonIdentifierDescription })
        XCTAssertEqual(items.count, 2)
    }

    func testArtworkIsJPEG() {
        let art = NativeNowPlayingMetadata.artworkItem(jpeg: Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(art.identifier, .commonIdentifierArtwork)
        XCTAssertEqual(art.dataType, kCMMetadataBaseDataType_JPEG as String)
        XCTAssertEqual(art.value as? Data, Data([0xFF, 0xD8, 0xFF]))
    }

    func testArtworkPrefersPoster() {
        var ctx = context(series: true, synopsis: nil)
        ctx.episodeStill = "https://img.example.com/still.jpg"
        XCTAssertEqual(NativeNowPlayingMetadata.artworkURL(context: ctx)?.lastPathComponent, "p.jpg")
    }
}
