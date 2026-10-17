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
}
