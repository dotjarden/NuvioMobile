import Foundation

/// Direction C D7/D8: the stream picker's focus decisions as pure functions of plain values, so
/// `StreamPickerFocusPolicyTests` can pin them and `StreamPickerView` only wires the results to its
/// `FocusState`. No SwiftUI. Every function answers "which key", never "write it": the view owns the
/// writes (async, verified) because focus code only works on the box with the engine in the loop.
///
/// Keys: the card is `StreamBestPickModel.focusKey` ("bestpick"), pills are "alt:fhd" / "alt:direct" /
/// "alt:all", a "more" row is "more:<section id>", chips are "chip:…"; everything else is a row key.
nonisolated enum StreamPickerFocusPolicy {
    static let pillPrefix = "alt:"
    static let morePrefix = "more:"

    // MARK: - Initial focus

    /// Where list focus goes first, for each body state: `.tiers` the card, else the first pill,
    /// else the first visible row; `.list` the first row (all of that is `body.firstFocusKey`).
    /// With nothing to list, `outcomeChipKey` (the selected chip once the fan-out ended with an
    /// outcome, nil while it is still unknown) so an empty result still leaves a control focused.
    /// Also the target after an auto-play cancel or a walk that gave up: the card when there is
    /// one, which the card's fixed key makes right whichever stream it holds by then.
    static func initialTarget(body: StreamPickerBodyModel, outcomeChipKey: String?) -> String? {
        body.firstFocusKey ?? outcomeChipKey
    }

    // MARK: - Transitions

    /// "Show all": focus goes to the first row of the A list that replaces the body.
    static func afterShowAll(firstRowKey: String?) -> String? { firstRowKey }

    /// Tier expand: the row that takes the "more" row's place. Read from the section BEFORE
    /// `expandSection` (the rebuilt section no longer has a hidden row).
    static func afterExpand(_ section: StreamTierPreviewSection) -> String? { section.firstHiddenKey }

    /// Card promotion (C-14): a pill took the initial focus because no stream was eligible yet, and
    /// the card has just appeared. Promote only while focus is still on that very pill; a viewer who
    /// moved off it is never pulled back. The caller supplies `cardAppeared` (false to true edge).
    static func promotesToCard(focused: String?, placed: String?, cardAppeared: Bool) -> Bool {
        guard cardAppeared, let focused, let placed else { return false }
        return placed.hasPrefix(pillPrefix) && focused == placed
    }

    /// Focus sat on a card, pill, row or "more" row that the rebuilt body no longer has. Nil when
    /// the focused key survived (or was never a body key). Rules:
    /// - "more:S" gone because S expanded -> S's first hidden row (the row that replaced it);
    /// - a row now hidden in a collapsed section S -> "more:S";
    /// - anything else (card gone, pill gone, row removed, `.tiers` -> `.list`) -> `new.firstFocusKey`.
    static func repairTarget(focused: String?, old: StreamPickerBodyModel,
                             new: StreamPickerBodyModel) -> String? {
        guard let focused, old.focusKeys.contains(focused), !new.focusKeys.contains(focused) else { return nil }
        if new.mode == .tiers {
            if focused.hasPrefix(morePrefix) {
                let sectionId = String(focused.dropFirst(morePrefix.count))
                if let hidden = old.sections.first(where: { $0.id == sectionId })?.firstHiddenKey,
                   new.focusKeys.contains(hidden) {
                    return hidden
                }
            } else if !focused.hasPrefix(pillPrefix), focused != StreamBestPickModel.focusKey,
                      let section = old.sections.first(where: { $0.visibleRows.contains { $0.key == focused } }),
                      let still = new.sections.first(where: { $0.id == section.id }),
                      still.hiddenCount > 0, new.focusKeys.contains(still.moreFocusKey) {
                return still.moreFocusKey
            }
        }
        return new.firstFocusKey
    }

    // MARK: - Moves

    /// Whether a Left/Right that reached the list's `onMoveCommand` from `focused` steps the source
    /// chips. The card, compact rows, "more" rows and `.list` full rows are full width, so the engine
    /// has no horizontal target and the press arrives; the pills share an HStack, the engine moves
    /// between them, and a chip step there would make the 2nd and 3rd pill unreachable (spec C-7).
    static func stepsChips(focused: String?) -> Bool {
        !(focused?.hasPrefix(pillPrefix) ?? false)
    }

    /// Down from the card: the engine picks the geometrically nearest pill (usually the trailing
    /// "Show all"); send it to the first pill instead. Nil unless the move was card -> a pill other
    /// than the first.
    static func downFromCardForward(old: String?, new: String?, body: StreamPickerBodyModel) -> String? {
        guard old == StreamBestPickModel.focusKey, let new, new.hasPrefix(pillPrefix),
              let first = body.alternatives.first?.focusKey, new != first else { return nil }
        return first
    }

    /// The chip forwarder's guard: a move FROM `key` onto a non-selected chip is forwarded to the
    /// selected chip only when `key` still belongs to the list (review r2: a key that left the
    /// hierarchy makes the engine fall back onto some chip, and that is not a move to forward).
    /// `rowKeys` answers "is this a row key of the current groups" (every row, collapsed or not);
    /// the body's own focus keys add the card, the pills and the "more" rows.
    static func isListKey(_ key: String, rowKeys: (String) -> Bool, body: StreamPickerBodyModel) -> Bool {
        // `.tiers`: only keys the body draws. A row pushed out of a preview by a republish is still in
        // the groups but is no longer a focus target, and forwarding from it fights the repair.
        body.mode == .tiers ? body.focusKeys.contains(key) : rowKeys(key)
    }
}
