import XCTest
import SwiftUI
import SharedCore
@testable import NuvioTV

/// Polish D1/W3-16 F2: a row at rest draws no file line, so a description never changes a resting row's height.
@MainActor
final class StreamRowDescriptionTests: XCTestCase {
    func testRestStateDrawsNoFileLine() {
        XCTAssertFalse(StreamRowDwell.showsLine(focused: true, dwelled: false, hasText: true))
        XCTAssertFalse(StreamRowDwell.showsLine(focused: false, dwelled: false, hasText: true))
    }

    func testDwelledFocusedRowWithTextDrawsTheFileLine() {
        XCTAssertTrue(StreamRowDwell.showsLine(focused: true, dwelled: true, hasText: true))
    }

    func testNoTextNeverDraws() {
        XCTAssertFalse(StreamRowDwell.showsLine(focused: true, dwelled: true, hasText: false))
        XCTAssertFalse(StreamRowDwell.showsLine(focused: true, dwelled: false, hasText: false))
    }

    func testLosingFocusCollapsesEvenAfterTheDwell() {
        XCTAssertFalse(StreamRowDwell.showsLine(focused: false, dwelled: true, hasText: true))
        XCTAssertFalse(StreamRowDwell.showsLine(focused: false, dwelled: true, hasText: false))
    }

    private func model(description: String?) -> StreamRowModel {
        let hints = StreamBehaviorHints(bingeGroup: nil, notWebReady: false, videoHash: nil, videoSize: nil,
                                        filename: nil, proxyHeaders: nil, audioDelayMs: nil)
        let stream = StreamItem(
            name: "Torrentio", title: nil, description: description, url: "https://cdn.example.com/a.mkv",
            infoHash: nil, fileIdx: nil, externalUrl: nil, ytId: nil, sources: [], sourceName: nil,
            addonName: "Add-on", addonId: "addon:x", addonLogo: nil, streamType: nil, behaviorHints: hints,
            clientResolve: nil, debridCacheStatus: nil, externalSubtitles: [], badges: [])
        return StreamRowModel.make(stream: stream, key: "k", display: StreamRowDisplay(),
                                   providerLabel: { $0.providerName })
    }

    func testARestingRowHasTheSameHeightWithOrWithoutADescription() {
        func height(_ description: String?) -> CGFloat {
            let view = StreamRowView(model: model(description: description), onSelect: {}, onBuiltIn: {},
                                     onExternal: { _ in })
            let host = UIHostingController(rootView: view.frame(width: 1200))
            return host.sizeThatFits(in: CGSize(width: 1200, height: 4000)).height
        }
        // The description carries no facts (the parser also reads it), so the rows differ only by the file line.
        let with = height("Some.Release.Name.With.No.Tags-GROUP")
        let without = height(nil)
        XCTAssertGreaterThan(without, 0)
        XCTAssertEqual(with, without, accuracy: 0.5, "rest draws no file line")
    }
}
