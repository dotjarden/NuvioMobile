import XCTest
@testable import NuvioTV

/// P4 (B17): late add-on subtitle renditions — merge and rebuild decision.
final class LateSubtitlePlanTests: XCTestCase {
    private let english = SubtitleRendition(index: 0, name: "English", language: "en",
                                            source: .remote(URL(string: "https://subs.example.com/a.srt")!))
    private let embedded = SubtitleRendition(index: 1, name: "French", language: "fr", source: .embedded(sink: 0))

    func testMergeContinuesIndicesAndDedupesNames() {
        let merged = LateSubtitlePlan.merge(existing: [english, embedded],
                                            late: [SubtitleFile(url: "https://subs.example.com/b.srt", language: "en", name: nil)])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].name, "English"); XCTAssertEqual(merged[0].index, 0)
        XCTAssertEqual(merged[1].name, "French"); XCTAssertEqual(merged[1].index, 1)
        XCTAssertEqual(merged[2].index, 2)
        XCTAssertEqual(merged[2].name, "English 2")
        XCTAssertEqual(merged[2].sourceURL?.absoluteString, "https://subs.example.com/b.srt")
    }

    func testMergeSkipsAlreadyServedURLs() {
        let merged = LateSubtitlePlan.merge(existing: [english],
                                            late: [SubtitleFile(url: "https://subs.example.com/a.srt", language: "en", name: nil)])
        XCTAssertEqual(merged.count, 1)
    }

    func testDecide() {
        let late = [SubtitleRendition(index: 2, name: "German", language: "de",
                                      source: .remote(URL(string: "https://subs.example.com/c.srt")!))]
        let def = [SubtitleRenditionFlags(autoselect: true, isDefault: true)]
        let plain = [SubtitleRenditionFlags(autoselect: true, isDefault: false)]
        XCTAssertEqual(LateSubtitlePlan.decide(late: late, flags: def, selectionShowing: false, legibleTouched: false, rebuildsUsed: 0),
                       .autoRebuild(name: "German"))
        XCTAssertEqual(LateSubtitlePlan.decide(late: late, flags: def, selectionShowing: false, legibleTouched: true, rebuildsUsed: 0), .publishOnly)
        XCTAssertEqual(LateSubtitlePlan.decide(late: late, flags: def, selectionShowing: true, legibleTouched: false, rebuildsUsed: 0), .publishOnly)
        XCTAssertEqual(LateSubtitlePlan.decide(late: late, flags: plain, selectionShowing: false, legibleTouched: false, rebuildsUsed: 0), .publishOnly)
        XCTAssertEqual(LateSubtitlePlan.decide(late: late, flags: def, selectionShowing: false, legibleTouched: false, rebuildsUsed: 1), .publishOnly)
        XCTAssertEqual(LateSubtitlePlan.decide(late: [], flags: [], selectionShowing: false, legibleTouched: false, rebuildsUsed: 0), .none)
    }
}
