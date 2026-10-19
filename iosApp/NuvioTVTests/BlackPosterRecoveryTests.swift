import XCTest
@testable import NuvioTV

/// Black poster (Steven rc3): a portrait poster in a row (the card an in-row trailer ran on, or a
/// neighbour) turned into a dark flat card and stayed that way. Three pure pieces pin the fix:
/// the orphan-stage watchdog decision, the "never hide the poster under an artless tile" rule, and
/// `CachedAsyncImage`'s same-picture test that keeps the image on screen across a decode change.
@MainActor
final class BlackPosterRecoveryTests: XCTestCase {

    // MARK: Watchdog

    func testGraceCoversTheLongestLegitimateCollapse() {
        // Deferred collapse from `.reveal` (reveal + morph), then shrink + dissolve (morph + reveal).
        let longest = 2 * InlineTrailerCardModel.revealDuration + 2 * InlineTrailerCardModel.morphDuration
        XCTAssertGreaterThan(InlineTrailerMorphPlan.watchdogGrace, longest)
        XCTAssertLessThan(InlineTrailerMorphPlan.watchdogGrace, 2.0)
    }

    func testOwnedOnlyWithActiveKeyAndExpandedPhase() {
        XCTAssertTrue(InlineTrailerMorphPlan.stageIsOwned(hasActiveKey: true, phaseExpanded: true))
        XCTAssertFalse(InlineTrailerMorphPlan.stageIsOwned(hasActiveKey: false, phaseExpanded: true))
        XCTAssertFalse(InlineTrailerMorphPlan.stageIsOwned(hasActiveKey: true, phaseExpanded: false))
        XCTAssertFalse(InlineTrailerMorphPlan.stageIsOwned(hasActiveKey: false, phaseExpanded: false))
    }

    func testWatchdogFiresOnlyOnAStrandedStagePastGrace() {
        let grace = InlineTrailerMorphPlan.watchdogGrace
        for stage in [InlineTrailerCardModel.MorphStage.reveal, .wide] {
            XCTAssertTrue(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: false, orphanedFor: grace))
            XCTAssertTrue(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: false, orphanedFor: 30))
            // Inside the grace: a collapse may still be running.
            XCTAssertFalse(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: false, orphanedFor: grace - 0.01))
            // A live pipeline (focused, trailer resolving or playing) is never touched, however long.
            XCTAssertFalse(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: true, orphanedFor: 30))
            XCTAssertFalse(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: true, orphanedFor: nil))
            XCTAssertFalse(InlineTrailerMorphPlan.watchdogShouldReset(stage: stage, owned: false, orphanedFor: nil))
        }
        XCTAssertFalse(InlineTrailerMorphPlan.watchdogShouldReset(stage: .none, owned: false, orphanedFor: 30))
    }

    // MARK: Base card visibility

    func testBaseCardHiddenOnlyUnderATileWithArt() {
        XCTAssertTrue(InlineTrailerMorphPlan.hidesBaseCard(fadesBaseCard: true, tileVisible: true, hasTileArt: true))
        // The dark card: tile showing with no art used to hide the poster under a flat surface.
        XCTAssertFalse(InlineTrailerMorphPlan.hidesBaseCard(fadesBaseCard: true, tileVisible: true, hasTileArt: false))
        XCTAssertFalse(InlineTrailerMorphPlan.hidesBaseCard(fadesBaseCard: true, tileVisible: false, hasTileArt: true))
        XCTAssertFalse(InlineTrailerMorphPlan.hidesBaseCard(fadesBaseCard: true, tileVisible: false, hasTileArt: false))
        // Landscape Posters: the base card always stays.
        XCTAssertFalse(InlineTrailerMorphPlan.hidesBaseCard(fadesBaseCard: false, tileVisible: true, hasTileArt: true))
    }

    // MARK: CachedAsyncImage same-picture test

    private let w500 = URL(string: "https://image.tmdb.org/t/p/w500/abc.jpg")!
    private let w780 = URL(string: "https://image.tmdb.org/t/p/w780/abc.jpg")!
    private let other = URL(string: "https://image.tmdb.org/t/p/w500/xyz.jpg")!
    private let medium = URL(string: "https://images.metahub.space/poster/medium/tt0111161/img")!
    private let large = URL(string: "https://images.metahub.space/poster/large/tt0111161/img")!
    private let addon = URL(string: "https://addon.example/tt1.jpg")!

    private func chain(_ urls: [URL]) -> ImageURLChain {
        ImageURLChain(urls: urls, request: .legacy)
    }

    func testSameHeadIsSameFamily() {
        XCTAssertTrue(chain([w500]).sharesURLFamily(with: chain([w500])))
        XCTAssertTrue(chain([addon]).sharesURLFamily(with: chain([addon, w500])))
    }

    func testCDNSizeVariantsAreSameFamily() {
        // The upgrade toggling with the drawn size swaps the head between renditions of one picture.
        XCTAssertTrue(chain([w780, w500]).sharesURLFamily(with: chain([w500])))
        XCTAssertTrue(chain([w500]).sharesURLFamily(with: chain([w780, w500])))
        XCTAssertTrue(chain([large, medium]).sharesURLFamily(with: chain([medium])))
    }

    func testDifferentPictureIsNotSameFamily() {
        XCTAssertFalse(chain([w500]).sharesURLFamily(with: chain([other])))
        XCTAssertFalse(chain([addon]).sharesURLFamily(with: chain([w500])))
        // Only the head counts: a shared fallback does not make two different pictures one.
        XCTAssertFalse(chain([other, addon]).sharesURLFamily(with: chain([w500, addon])))
    }

    func testEmptyChainIsNeverSameFamily() {
        XCTAssertFalse(chain([]).sharesURLFamily(with: chain([w500])))
        XCTAssertFalse(chain([w500]).sharesURLFamily(with: chain([])))
        XCTAssertFalse(chain([]).sharesURLFamily(with: chain([])))
    }
}
