import XCTest
@testable import NuvioTV
import SharedCore

/// Unit tests for `TitleLogoStore`'s pure, store-free functions (`DesignSystem/TitleLogoStore.swift`,
/// moved out of `SagaCard.swift` and renamed from `SagaLogoStore` for FEAT-42). Deliberately does
/// NOT drive the singleton itself — `lookupIfNeeded`/`logoURL(for:)`/`awaitLogoURL(for:)` all reach
/// `TmdbSettingsRepository.shared`/`TmdbMetadataService.shared`, real process-wide singletons with
/// no injection seam and no test-only mutators, so a test that touched the singleton would be
/// exercising ambient global state rather than this store's own logic. `shouldCommit` and
/// `waitDecision` are `nonisolated static` with no store/dictionary access specifically so their
/// full decision tables can be pinned here with no live store at all; `isLookupCandidate` and
/// `key(for:)` are likewise pure. `SagaCard`'s use of the store (the async fetch/cache path) stays
/// covered indirectly by `SagaCardTests`' `needsLogoLookup` cases and by the device/UI passes.
final class TitleLogoStoreTests: XCTestCase {

    private func makeItem(id: String = "1", type: String = "movie", logo: String? = nil) -> MetaPreview {
        MetaPreview(
            id: id, type: type, name: "Movie",
            poster: nil, banner: nil, logo: logo,
            posterShape: .landscape,
            description: nil, releaseInfo: nil, rawReleaseDate: nil,
            popularity: nil, voteCount: nil, imdbRating: nil,
            genres: []
        )
    }

    // MARK: - shouldCommit (moved from SagaCardTests, formerly SagaLogoStore.shouldCommit)
    //
    // Codex r2 findings 3+4: a lookup's completion must only be written to the cache when it is
    // still the live `.pending` attempt for its key. `shouldCommit` is the pure decision behind
    // that — no store, no dictionary, just the entry that was read for a key and the request id
    // the completion carries.

    func testShouldCommitTrueForMatchingPending() {
        XCTAssertTrue(TitleLogoStore.shouldCommit(entry: .pending(requestId: 7), requestId: 7))
    }

    func testShouldCommitFalseForDifferentRequestId() {
        // A newer `lookupIfNeeded` call for the same key installed its own `.pending` — this
        // (older) request's completion must not clobber it.
        XCTAssertFalse(TitleLogoStore.shouldCommit(entry: .pending(requestId: 7), requestId: 3))
    }

    func testShouldCommitFalseWhenAlreadyResolved() {
        XCTAssertFalse(TitleLogoStore.shouldCommit(entry: .resolved("https://example.com/logo.png"), requestId: 7))
    }

    func testShouldCommitFalseWhenEntryMissing() {
        // The key was never populated, or its `.pending` was wiped by a capacity reset.
        XCTAssertFalse(TitleLogoStore.shouldCommit(entry: nil, requestId: 7))
    }

    // MARK: - waitDecision (FEAT-42, behind `awaitLogoURL(for:)`)
    //
    // The anti-hang invariant: every branch either answers immediately (`.answer`) or parks
    // (`.park`) behind a `.pending` entry that WILL eventually resolve (`lookupIfNeeded`'s
    // completion) or be removed (the off-scope path) — both of which resume every parked waiter.
    // A missing entry must answer, never park, since nothing will ever write to a key nobody
    // asked `lookupIfNeeded` to look up.

    func testWaitDecisionParksOnPending() {
        XCTAssertEqual(TitleLogoStore.waitDecision(entry: .pending(requestId: 1)), .park)
    }

    func testWaitDecisionAnswersWithTheResolvedURL() {
        XCTAssertEqual(TitleLogoStore.waitDecision(entry: .resolved("https://example.com/logo.png")),
                       .answer("https://example.com/logo.png"))
    }

    func testWaitDecisionAnswersNilForAResolvedNoLogoResult() {
        // A completed lookup that found nothing is a real, final answer — not a reason to keep
        // waiting or to re-attempt.
        XCTAssertEqual(TitleLogoStore.waitDecision(entry: .resolved(nil)), .answer(nil))
    }

    func testWaitDecisionAnswersNilForAMissingEntry() {
        // Nobody has called `lookupIfNeeded` for this key — parking here would hang forever.
        XCTAssertEqual(TitleLogoStore.waitDecision(entry: nil), .answer(nil))
    }

    // MARK: - isLookupCandidate

    func testIsLookupCandidateTrueForNil() {
        XCTAssertTrue(TitleLogoStore.isLookupCandidate(nil))
    }

    func testIsLookupCandidateTrueForBlank() {
        XCTAssertTrue(TitleLogoStore.isLookupCandidate(""))
    }

    func testIsLookupCandidateFalseForANonBlankLogo() {
        XCTAssertFalse(TitleLogoStore.isLookupCandidate("https://example.com/logo.png"))
    }

    // MARK: - key(for:)

    func testKeyCombinesTypeAndId() {
        let item = makeItem(id: "42", type: "series")
        XCTAssertEqual(TitleLogoStore.key(for: item), "series|42")
    }

    func testKeyDiffersForDifferentTypesWithTheSameId() {
        let movie = makeItem(id: "42", type: "movie")
        let series = makeItem(id: "42", type: "series")
        XCTAssertNotEqual(TitleLogoStore.key(for: movie), TitleLogoStore.key(for: series))
    }

    // MARK: - completionOutcome (FEAT-42 crash fix, 2026-09-12)
    //
    // The pure decision behind `lookupOne`'s post-guard branching, once `shouldCommit`/scope have
    // already passed. A failed lookup (an `NSError` surfaced through `fetchPreviewEnrichmentChecked`'s
    // `@Throws` bridge instead of aborting the process) must never be written as `.resolved(nil)` —
    // only a completed lookup that found a real logo, or one that completed and found nothing, is
    // recorded that way.

    func testCompletionOutcomeResolvedForANonBlankLogo() {
        let enrichment = TmdbPreviewEnrichment(
            localizedTitle: nil, description: nil, genres: [],
            logo: "https://example.com/logo.png", backdrop: nil
        )
        XCTAssertEqual(
            TitleLogoStore.completionOutcome(enrichment: enrichment, error: nil),
            .resolved("https://example.com/logo.png")
        )
    }

    func testCompletionOutcomeResolvedNoneForAMissingLogo() {
        let enrichment = TmdbPreviewEnrichment(
            localizedTitle: nil, description: nil, genres: [],
            logo: nil, backdrop: nil
        )
        XCTAssertEqual(TitleLogoStore.completionOutcome(enrichment: enrichment, error: nil), .resolvedNone)
    }

    func testCompletionOutcomeFailedOnAnyError() {
        // A network error, timeout, HTTP 429, or JSON decode failure inside the lookup — any
        // non-nil error, regardless of what enrichment (if anything) also came back — must never
        // latch a permanent "no logo" answer.
        let error = NSError(domain: "TitleLogoStoreTests", code: 1)
        XCTAssertEqual(TitleLogoStore.completionOutcome(enrichment: nil, error: error), .failed)
    }
}
