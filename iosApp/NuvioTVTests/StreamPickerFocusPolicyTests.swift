import XCTest
@testable import NuvioTV

/// Direction C D7/D8: `StreamPickerFocusPolicy`, the picker's focus decisions as pure functions of
/// plain values. The view only wires the answers to its `FocusState`.
@MainActor
final class StreamPickerFocusPolicyTests: XCTestCase {

    // MARK: - Builders

    private func row(_ key: String) -> StreamRowModel {
        StreamRowModel(
            key: key, title: key, description: nil, badges: [], sizeBytes: nil, badgesOnTop: false,
            showsAddonColumn: false, showsAddonName: true, addonName: "A", addonLogo: nil, isYouTube: false,
            playbackKey: "pk-" + key, resolution: nil, headline: "1080p", hdrMark: nil, videoFacts: [],
            audioFacts: [], cachedState: nil
        )
    }

    /// One "1080p" tier of `count` rows named r0, r1, ...
    private func tier(_ count: Int) -> [StreamListSection] {
        [StreamListSection(id: "tier|FHD", title: "1080p", count: count, isLoading: false, showsLabel: true,
                           rows: (0..<count).map { row("r\($0)") })]
    }

    private func body(rows: Int = 4, best: String? = "r0", fhd: String? = "r1", direct: String? = nil,
                      expanded: Set<String> = []) -> StreamPickerBodyModel {
        StreamPickerBodyModel.build(
            mode: .tiers, sections: tier(rows), firstRowKey: "r0",
            selection: StreamBestPickSelection(bestKey: best, fhdKey: fhd, directKey: direct),
            settled: true, expanded: expanded)
    }

    private func listBody() -> StreamPickerBodyModel {
        StreamPickerBodyModel.build(mode: .list, sections: tier(4), firstRowKey: "r0", selection: .none,
                                    settled: true, expanded: [])
    }

    // MARK: - Initial focus

    func testInitialFocusForEachBodyState() {
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: body(), outcomeChipKey: nil), "bestpick",
                       "a card: the card")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: body(best: nil), outcomeChipKey: nil), "alt:fhd",
                       "no card: the first pill")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: body(best: nil, fhd: nil), outcomeChipKey: nil),
                       "alt:all", "only Show all")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: listBody(), outcomeChipKey: nil), "r0",
                       ".list: the first row")
        let manual = StreamPickerBodyModel(mode: .tiers, firstFocusKey: "r0")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: manual, outcomeChipKey: "chip:all"), "r0",
                       "no card and no pill: the first visible row")
    }

    func testAnEmptyResultFallsBackToTheOutcomeChip() {
        let empty = StreamPickerBodyModel()
        XCTAssertNil(empty.firstFocusKey)
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: empty, outcomeChipKey: "chip:all"), "chip:all")
        XCTAssertNil(StreamPickerFocusPolicy.initialTarget(body: empty, outcomeChipKey: nil),
                     "outcome still unknown: nothing to place yet")
    }

    func testAnAutoPlayCancelLandsOnTheCardWhateverItHolds() {
        // The same call serves the cancel: the card's fixed key is right for any stream behind it.
        let before = body(best: "r0")
        let after = body(best: "r2")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: before, outcomeChipKey: nil), "bestpick")
        XCTAssertEqual(StreamPickerFocusPolicy.initialTarget(body: after, outcomeChipKey: nil), "bestpick")
    }

    // MARK: - Show all, expand

    func testAfterShowAllIsTheFirstRowOfTheList() {
        XCTAssertEqual(StreamPickerFocusPolicy.afterShowAll(firstRowKey: "k"), "k")
        XCTAssertNil(StreamPickerFocusPolicy.afterShowAll(firstRowKey: nil))
    }

    func testAfterExpandIsTheFirstHiddenRow() {
        let section = body(rows: 4).sections[0]
        XCTAssertEqual(section.hiddenCount, 2)
        XCTAssertEqual(StreamPickerFocusPolicy.afterExpand(section), "r2")
        XCTAssertNil(StreamPickerFocusPolicy.afterExpand(body(rows: 2).sections[0]), "nothing hidden")
    }

    // MARK: - Promotion (C-14)

    func testPromotesToTheCardOnlyWhileFocusStillSitsOnThePlacedPill() {
        XCTAssertTrue(StreamPickerFocusPolicy.promotesToCard(focused: "alt:all", placed: "alt:all", cardAppeared: true))
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: "alt:fhd", placed: "alt:all", cardAppeared: true),
                       "the viewer moved to another pill")
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: "r0", placed: "alt:all", cardAppeared: true),
                       "the viewer moved to a row")
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: "r0", placed: "r0", cardAppeared: true),
                       "placed on a row: never promoted")
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: "alt:all", placed: "alt:all", cardAppeared: false),
                       "no card edge")
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: nil, placed: "alt:all", cardAppeared: true))
        XCTAssertFalse(StreamPickerFocusPolicy.promotesToCard(focused: "alt:all", placed: nil, cardAppeared: true))
    }

    // MARK: - Repair

    func testARowNowHiddenInACollapsedSectionRepairsToItsMoreRow() {
        let old = body(rows: 4, expanded: ["tier|FHD"])
        let new = body(rows: 4)
        XCTAssertTrue(old.focusKeys.contains("r3"))
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "r3", old: old, new: new), "more:tier|FHD")
    }

    func testTheMoreRowRepairsToTheFirstHiddenRowAfterTheExpand() {
        let old = body(rows: 4)
        let new = body(rows: 4, expanded: ["tier|FHD"])
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "more:tier|FHD", old: old, new: new), "r2")
    }

    func testAGoneCardOrPillRepairsToTheNewFirstFocusKey() {
        let withCard = body()
        let noCard = body(best: nil, fhd: nil)
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "bestpick", old: withCard, new: noCard), "alt:all")
        let noPill = body(best: "r0", fhd: nil)
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "alt:fhd", old: withCard, new: noPill), "bestpick")
    }

    func testTiersToListRepairsToTheFirstRow() {
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "bestpick", old: body(), new: listBody()), "r0")
        XCTAssertEqual(StreamPickerFocusPolicy.repairTarget(focused: "alt:all", old: body(), new: listBody()), "r0")
    }

    func testNoRepairWhenTheFocusedKeySurvivedOrWasNeverABodyKey() {
        let old = body()
        XCTAssertNil(StreamPickerFocusPolicy.repairTarget(focused: "bestpick", old: old, new: body(best: "r2")),
                     "the card key is fixed")
        XCTAssertNil(StreamPickerFocusPolicy.repairTarget(focused: nil, old: old, new: body(best: nil, fhd: nil)))
        XCTAssertNil(StreamPickerFocusPolicy.repairTarget(focused: "chip:all", old: old, new: body(best: nil, fhd: nil)))
        XCTAssertNil(StreamPickerFocusPolicy.repairTarget(focused: "r3", old: old, new: old),
                     "r3 is hidden in both: it was never a body key")
    }

    // MARK: - Moves

    func testStepsChipsExceptFromPills() {
        XCTAssertFalse(StreamPickerFocusPolicy.stepsChips(focused: "alt:fhd"))
        XCTAssertFalse(StreamPickerFocusPolicy.stepsChips(focused: "alt:direct"))
        XCTAssertFalse(StreamPickerFocusPolicy.stepsChips(focused: "alt:all"))
        XCTAssertTrue(StreamPickerFocusPolicy.stepsChips(focused: "bestpick"))
        XCTAssertTrue(StreamPickerFocusPolicy.stepsChips(focused: "r0"))
        XCTAssertTrue(StreamPickerFocusPolicy.stepsChips(focused: "more:tier|FHD"))
        XCTAssertTrue(StreamPickerFocusPolicy.stepsChips(focused: nil))
    }

    func testDownFromTheCardForwardsToTheFirstPill() {
        let b = body(best: "r0", fhd: "r1")
        XCTAssertEqual(b.alternatives.map(\.focusKey), ["alt:fhd", "alt:all"])
        XCTAssertEqual(StreamPickerFocusPolicy.downFromCardForward(old: "bestpick", new: "alt:all", body: b), "alt:fhd")
        XCTAssertNil(StreamPickerFocusPolicy.downFromCardForward(old: "bestpick", new: "alt:fhd", body: b),
                     "already the first pill")
        XCTAssertNil(StreamPickerFocusPolicy.downFromCardForward(old: "r0", new: "alt:all", body: b),
                     "not a move from the card")
        XCTAssertNil(StreamPickerFocusPolicy.downFromCardForward(old: "bestpick", new: "r0", body: b),
                     "not a move onto a pill")
        XCTAssertNil(StreamPickerFocusPolicy.downFromCardForward(old: "bestpick", new: nil, body: b))
    }

    func testIsListKey() {
        let b = body()
        let rowKeys: (String) -> Bool = { ["r0", "r1", "r2", "r3"].contains($0) }
        XCTAssertFalse(StreamPickerFocusPolicy.isListKey("r3", rowKeys: rowKeys, body: b),
                       "row hidden in a preview is not a list key in .tiers")
        XCTAssertTrue(StreamPickerFocusPolicy.isListKey("r3", rowKeys: rowKeys, body: listBody()),
                      ".list: every group row key counts")
        XCTAssertTrue(StreamPickerFocusPolicy.isListKey("bestpick", rowKeys: rowKeys, body: b))
        XCTAssertTrue(StreamPickerFocusPolicy.isListKey("alt:all", rowKeys: rowKeys, body: b))
        XCTAssertTrue(StreamPickerFocusPolicy.isListKey("more:tier|FHD", rowKeys: rowKeys, body: b))
        XCTAssertFalse(StreamPickerFocusPolicy.isListKey("chip:x", rowKeys: rowKeys, body: b))
        XCTAssertFalse(StreamPickerFocusPolicy.isListKey("bestpick", rowKeys: rowKeys, body: listBody()),
                       "the card is not a key of a .list body")
    }
}
