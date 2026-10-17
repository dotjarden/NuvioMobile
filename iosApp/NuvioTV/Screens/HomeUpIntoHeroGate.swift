import Foundation

/// beta.18 verdict (BUG-112 residue): the pure decision half of `HomeView.revealTopAfterUpIntoHero`
/// — whether a hero focus gain that follows an Up input should scroll the rows back to the top.
/// Extracted so every decline carries a reason string (the success path alone used to log, so a
/// tester's "it did nothing" could not be diagnosed) and so the gate order is unit-testable.
/// All timestamps are `systemUptime` values.
enum HomeUpIntoHeroGate {
    enum Verdict: Equatable {
        case reveal
        case declined(reason: String)
    }

    /// Gate order: rows not scrolled past the top, then the Up input must be inside `window`, then
    /// focus must have come from a row (a row still on record, or one that released focus inside
    /// `window`). `lastUpInputAt == -1` means never.
    /// review r1 (P3-3): `alreadyRevealing` (a reveal within the last 0.5 s) is declined by
    /// `HomeView.revealTopAfterUpIntoHero` itself via `HomeRowInputBox.lastRevealAt`, after this gate.
    ///
    /// 2026-10-17 (folder-return Up-skip): `originHasRowAbove` waives the past-top check. A row with
    /// a row above it never legitimately hands an Up to the hero, so that gain is a skip wherever
    /// the rows sit; and after a folder pop the engine's own scroll toward the CTA brings the rows
    /// back to the top BEFORE this runs, so the past-top reading said `notPastTop` on every skip.
    nonisolated static func evaluate(now: TimeInterval,
                                     lastUpInputAt: TimeInterval,
                                     lastRowReleasedAt: TimeInterval?,
                                     focusedRowKey: String?,
                                     rowsScrolledPastTop: Bool,
                                     originHasRowAbove: Bool = false,
                                     window: TimeInterval) -> Verdict {
        guard rowsScrolledPastTop || originHasRowAbove else { return .declined(reason: "notPastTop") }
        let sinceUp = now - lastUpInputAt
        guard sinceUp < window else {
            return .declined(reason: "staleInput sinceUp=\(Int((sinceUp * 1000).rounded()))")
        }
        let sinceRelease = lastRowReleasedAt.map { now - $0 }
        let cameFromRow = focusedRowKey != nil || (sinceRelease.map { $0 < window } ?? false)
        guard cameFromRow else {
            let ms = sinceRelease.map { String(Int(($0 * 1000).rounded())) } ?? "none"
            return .declined(reason: "noRowOrigin sinceRelease=\(ms)")
        }
        return .reveal
    }

    /// Folder-return Up-skip (review r1 P2-1): whether a hero focus gain is the focus engine
    /// resolving an Up from a row onto the CTA, as opposed to Home writing the hero focus itself
    /// (Menu to the top, the BUG-112 ladder's hero rung, a rail exit) or a hero focused earlier
    /// that now receives an Up. All three must hold:
    ///  - no programmatic hero write inside `window`;
    ///  - the gain and the row's release came in the same update (within `sameUpdate`); a row that
    ///    still owns focus on record (`rowStillOwned`, its release not yet reported) counts as
    ///    releasing at the gain;
    ///  - the Up input sits around the gain: up to `inputLead` before it, or up to `inputLag` after
    ///    it (`window` by default; on hardware the press reaches the app 30–180 ms after the focus
    ///    update, a slow swipe at gesture end).
    nonisolated static func isEngineSkip(now: TimeInterval,
                                         heroGainedAt: TimeInterval?,
                                         rowReleasedAt: TimeInterval?,
                                         rowStillOwned: Bool,
                                         lastUpInputAt: TimeInterval,
                                         programmaticHeroAt: TimeInterval?,
                                         window: TimeInterval,
                                         sameUpdate: TimeInterval = 0.15,
                                         inputLead: TimeInterval = 0.3,
                                         inputLag: TimeInterval? = nil) -> Bool {
        guard let gained = heroGainedAt, now - gained < window else { return false }
        if let written = programmaticHeroAt, now - written < window { return false }
        guard let released = rowStillOwned ? gained : rowReleasedAt,
              abs(gained - released) < sameUpdate else { return false }
        guard lastUpInputAt >= 0 else { return false }
        let offset = lastUpInputAt - gained
        // Review r2 (P3-2): the lag defaults to the whole window, so a slow swipe recognised at
        // gesture end still counts.
        return offset > -inputLead && offset < (inputLag ?? window)
    }
}
