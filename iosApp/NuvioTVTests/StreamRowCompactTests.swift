import SwiftUI
import UIKit
import XCTest
@testable import NuvioTV

/// Direction C §5.6: the compact row's one-line composition (`StreamPickerCopy.compactParts`,
/// `compactSpokenLabel`) and its fixed height.
@MainActor
final class StreamRowCompactTests: XCTestCase {

    private func row(title: String = "Torrentio", headline: String? = "1080p", hdrMark: String? = nil,
                     videoFacts: [String] = [], audio: String? = nil, cached: StreamRowCachedState? = nil,
                     size: Int64? = nil, addon: String = "Torrentio", failed: Bool = false,
                     youtube: Bool = false, description: String? = nil) -> StreamRowModel {
        StreamRowModel(
            key: "k", title: title, description: description, badges: [], sizeBytes: size, badgesOnTop: false,
            showsAddonColumn: false, showsAddonName: true, addonName: addon, addonLogo: nil, isYouTube: youtube,
            playbackKey: "pk", resolution: nil, headline: headline, hdrMark: hdrMark, videoFacts: videoFacts,
            audioFacts: [], cachedState: cached, audio: audio, failedRecently: failed
        )
    }

    func testLeadIsTheHeadlineWithTheShortHdrMark() {
        XCTAssertEqual(StreamPickerCopy.compactParts(row(headline: "4K", hdrMark: "DV · HDR10")).lead,
                       "4K DV · HDR10")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(headline: "1080p", hdrMark: nil)).lead, "1080p")
    }

    func testLeadFallsBackToTheTitle() {
        XCTAssertEqual(StreamPickerCopy.compactParts(row(title: "Some Release", headline: nil)).lead, "Some Release")
    }

    func testFactsAreVideoTermsThenAudio() {
        XCTAssertEqual(StreamPickerCopy.compactParts(row(videoFacts: ["WEB-DL", "HEVC"], audio: "Atmos DD+ 5.1")).facts,
                       "WEB-DL · HEVC · Atmos DD+ 5.1")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(videoFacts: ["WEB-DL", "HEVC"], audio: nil)).facts,
                       "WEB-DL · HEVC", "no audio: video terms alone")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(videoFacts: [], audio: "AAC")).facts, "AAC")
        XCTAssertNil(StreamPickerCopy.compactParts(row(videoFacts: [], audio: nil)).facts, "no facts at all")
    }

    func testCachedGlyph() {
        XCTAssertNil(StreamPickerCopy.compactParts(row(cached: nil)).glyph, "no cached state: no glyph")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(cached: .notCached)).glyph, "arrow.down.circle")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(cached: .instant(provider: "TB"))).glyph, "checkmark.circle")
    }

    func testSizeFollowsTheRow() {
        XCTAssertNil(StreamPickerCopy.compactParts(row(size: nil)).size, "File Size Badges off or no size")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(size: 2_000_000_000)).size,
                       StreamFileSizeChip.label(for: 2_000_000_000))
    }

    func testTrailingIsFailedRecentlyElseTheAddonName() {
        XCTAssertEqual(StreamPickerCopy.compactParts(row(addon: "Comet", failed: true)).trailing, "Failed recently")
        XCTAssertEqual(StreamPickerCopy.compactParts(row(addon: "Comet", failed: false)).trailing, "Comet")
        XCTAssertNil(StreamPickerCopy.compactParts(row(addon: "", failed: false)).trailing, "empty add-on name")
        XCTAssertNil(StreamPickerCopy.compactParts(row(addon: "  ", failed: false)).trailing)
    }

    func testSpokenLabelOrder() {
        let size: Int64 = 3_000_000_000
        let r = row(headline: "4K", hdrMark: "DV", videoFacts: ["WEB-DL", "HEVC"], audio: "Atmos",
                    cached: .instant(provider: "TB"), size: size, addon: "Comet", failed: true, youtube: true)
        XCTAssertEqual(StreamPickerCopy.compactSpokenLabel(r),
                       ["4K DV", "WEB-DL", "HEVC", "Atmos", "TB Instant", StreamFileSizeChip.label(for: size),
                        "Comet", "YouTube", "Failed recently"].joined(separator: ", "))
        XCTAssertEqual(StreamPickerCopy.compactSpokenLabel(row(headline: "1080p", addon: "")), "1080p")
    }

    // MARK: - Hosted height

    private func height(of model: StreamRowModel) -> CGFloat {
        let view = StreamCompactRowView(model: model, onSelect: {}, onBuiltIn: {}, onExternal: { _ in })
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func testTheRowIsOneFixedLineWhateverTheDescription() {
        let plain = height(of: row(size: 1_000_000_000))
        let described = height(of: row(size: 1_000_000_000,
                                        description: "Movie.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HEVC-GROUP"))
        XCTAssertGreaterThanOrEqual(plain, StreamCompactRowView.Metrics.height)
        XCTAssertGreaterThanOrEqual(plain, 64)
        XCTAssertEqual(plain, described, accuracy: 0.5, "the compact row draws no file line")
    }
}
