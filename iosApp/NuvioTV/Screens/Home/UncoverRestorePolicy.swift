import Foundation

// BUG-156 (b) + (a) (Steven, beta.19-rc4 verdict 2026-10-16: "the return from a collection, and from
// a movie inside a collection, still jumps"). The pure halves of the strip's pop restore, so
// `UncoverRestorePolicyTests` pins them without a view host:
//
//  - `UncoverRestorePolicy`: what a strip row change (or focus leaving the strip) means while a pop
//    restore is live: the restore landing, the focus engine's own late restoration (re-grab), or the
//    viewer's own move (retire).
//  - `FolderPushOrigin`: which row and card a push over the folder Rows page leaves from (the folder
//    page sees the push only at its `onDisappear`, after focus has already gone to the pushed page).

/// See the file header.
nonisolated enum UncoverRestorePolicy {
    /// The re-grab window once the restore has LANDED on its row (the first row change to the target
    /// after the request). The Living Room ATV measured the engine's late restoration 0.55–0.98 s
    /// after ours (Batch A device pass, step 8); Steven's box (No Zoom, In Row trailers, Medium+)
    /// still jumped with a 1.2 s window counted from the REQUEST, which the rung delays and the pager
    /// glide eat into. Counted from the landing, 1.5 s covers both.
    static let landedWindow: TimeInterval = 1.5
    /// The old rule, kept for a restore that never landed: the window from the request.
    static let unlandedWindow: TimeInterval = 1.2
    /// Re-grabs per restore while the viewer has made no input. Classic's device walk saw the engine
    /// fire its default-candidate restoration TWICE (0.59 s and 0.98 s after the pop) and settled on
    /// three (`HomeView.heroRegrabLimit`). The old "a second move is the viewer's" rule predates the
    /// viewer-input clock (`ViewerInputClock`): a viewer move now retires the restore by itself, so a
    /// further move with no input since the pop is the engine again. Without a live clock the old
    /// rule stands (`maxRegrabs(clockLive: false)` = 1).
    static func maxRegrabs(clockLive: Bool) -> Int { clockLive ? 3 : 1 }
    /// A re-grab is issued this long after the move that asked for it, and only if the viewer has
    /// still made no input: a directional press reaches the window's recognizers after the focus
    /// engine has already moved (`HomeUpSwipeCatcher`'s note), so the press that caused a row change
    /// can be stamped a beat after the row change it caused. `HomeUpSwipeCatcher.settleWindow`'s value.
    static let regrabDefer: TimeInterval = 0.15

    /// A live restore. `requestedAt` is the pop (when `restoreAfterUncover` was called), `issuedAt`
    /// when the request went to the pager (the pager may not be installed yet at the pop).
    struct Target: Equatable {
        let rowKey: String
        let itemId: String?
        let requestedAt: TimeInterval
        let issuedAt: TimeInterval
        var landedAt: TimeInterval?
        var regrabs = 0
    }

    enum Action: Equatable {
        /// The target row took focus for the first time: record the landing.
        case land
        /// Nothing to do (the target row again, after a landing or a re-grab).
        case keep
        /// The engine moved focus off the target with no viewer input: ask for the target again.
        /// `age` is measured from `from` ("landing" or "request").
        case regrab(age: TimeInterval, from: String)
        /// The restore is over (`viewer`, `expired`, `limit`).
        case retire(String)
    }

    /// `key` is the row that now owns focus, nil when focus left the strip. `viewerInputAt` is the
    /// last viewer input (`ViewerInputClock.lastAt`), nil when the clock has none.
    static func decide(_ target: Target,
                       key: String?,
                       now: TimeInterval,
                       viewerInputAt: TimeInterval?,
                       clockLive: Bool) -> Action {
        if viewerMoved(target, viewerInputAt: viewerInputAt) { return .retire("viewer") }
        if key == target.rowKey {
            return target.landedAt == nil ? .land : .keep
        }
        let from = target.landedAt == nil ? "request" : "landing"
        let reference = target.landedAt ?? target.issuedAt
        let window = target.landedAt == nil ? unlandedWindow : landedWindow
        let age = now - reference
        guard age < window else { return .retire("expired") }
        guard target.regrabs < maxRegrabs(clockLive: clockLive) else { return .retire("limit") }
        return .regrab(age: age, from: from)
    }

    /// A viewer input at or after the pop. The press that popped (Menu) began before the pop edge,
    /// so it never counts.
    static func viewerMoved(_ target: Target, viewerInputAt: TimeInterval?) -> Bool {
        guard let viewerInputAt else { return false }
        return viewerInputAt >= target.requestedAt
    }

    /// BUG-188 (Steven rc9; rig log 2026-10-19, `console-bug188.log`): ~40 ms after `restore
    /// landed`, the engine's late restoration moved focus to `UIKitFocusableFillerItem` at y = −218,
    /// the row above's horizontal-scroller stand-in, which the gate's `.disabled` does not cover
    /// (the BUG-176 class). The deferred re-grab (`regrabDefer`) left it there ~195 ms: the landed
    /// card's single flicker. No stage swap happened, so holding swaps would change nothing.
    ///
    /// A filler under a CLOSED gate is never a viewer's target (every other row is disabled, and a
    /// viewer press retires the restore before this is asked), so the re-grab skips the defer and
    /// runs in the same turn. Without the gate, or after a viewer input since the landing, the
    /// deferred path stands.
    static func regrabsImmediately(fillerFocused: Bool, gateClosed: Bool, viewerInputSinceLanding: Bool) -> Bool {
        fillerFocused && gateClosed && !viewerInputSinceLanding
    }

    /// SwiftUI's stand-in for a lazy row's scroller (`UIKitFocusableFillerItem`), by its runtime type
    /// name: a private type, so the name is all there is to match on.
    static func isFocusableFiller(typeName: String) -> Bool {
        typeName.contains("FocusableFillerItem")
    }
}

/// Batch N (BUG-188 follow-up; Steven rc9: an Up pressed during the collection pop is lost). A
/// viewer Up or Down that retires a live pop restore either went nowhere (the restore's gate left
/// every other row disabled, or the pager was not back yet) or was made by the engine itself. This
/// decides the move to replay: the neighbouring row of the anchor, or nil when there is nothing to
/// replay. It folds BUG-176's landed-case replay in, so there is one rule for both retire branches.
nonisolated enum UncoverReplayPolicy {
    /// Batch N device pass (2026-10-20): positions, not timestamps. On hardware the engine's late
    /// pop restoration moves focus a row the WRONG way 100–150 ms after the viewer's Up (log:
    /// `PRESS 2→3 vfocus-down` right after `retired … input=up`), so "a row change after the press"
    /// can't tell the engine answering the viewer from the engine ignoring them. The viewer's
    /// target is the restore row's neighbour in the pressed direction; if focus is already there
    /// the engine made the move and nothing replays, otherwise the replay goes there.
    /// - Parameters:
    ///   - kind: the viewer input; only `.up` and `.down` replay.
    ///   - currentRowKey: the strip row that owns focus now, nil when the strip owns none.
    ///   - restoreRowKey: the row the pop restore was taking focus back to, the row the viewer
    ///     pressed from.
    ///   - rowKeys: the strip's rows in order (`pagerHandle.rowKeys`).
    /// - Returns: the destination row key; nil at the strip's bounds, when focus is already on it,
    ///   or when the restore row is unknown.
    static func decide(kind: ViewerInputKind,
                       currentRowKey: String?,
                       restoreRowKey: String?,
                       rowKeys: [String]) -> String? {
        guard kind == .up || kind == .down,
              let restoreRowKey, let index = rowKeys.firstIndex(of: restoreRowKey) else { return nil }
        let next = kind == .down ? index + 1 : index - 1
        guard rowKeys.indices.contains(next) else { return nil }
        let destination = rowKeys[next]
        return currentRowKey == destination ? nil : destination
    }
}

/// See the file header. The folder Rows page learns of a push over it only at its `onDisappear`,
/// which runs at the END of the push transition; by then focus has gone to the pushed Detail and the
/// strip has reported the loss (`onStripFocusLost`). So the loss records the row and card it left,
/// and the disappear decides whether that loss was this push.
nonisolated enum FolderPushOrigin {
    struct Origin: Equatable {
        let rowKey: String
        let itemId: String?
    }

    /// Without a live viewer-input clock: a loss this recent before the disappear is the push's.
    static let lossGrace: TimeInterval = 1.5
    /// With the clock: the Select that pushed (or opened the hold menu whose "Go to Details" pushed)
    /// came at most this long before the loss. A hold menu opens ~0.5–1 s into the hold.
    static let selectToLossGrace: TimeInterval = 2.0

    /// - Parameters:
    ///   - current: the strip's focused row and its remembered card, when a strip row still owns
    ///     focus at the disappear (the loss has not been reported yet).
    ///   - lost: the row and card the strip left at its last focus loss.
    ///   - sinceLoss: seconds from that loss to the disappear (nil = no loss recorded).
    ///   - inputBeforeLoss: the last viewer input before the loss (`ViewerInput`: its kind and how
    ///     long before the loss it came); nil without a clock.
    ///   - railArmedSinceLoss: the rail armed after the loss (a Left into the rail, then a tab: not a
    ///     push; the rail's own return route restores that one).
    static func resolve(current: Origin?,
                        lost: Origin?,
                        sinceLoss: TimeInterval?,
                        inputBeforeLoss: ViewerInput?,
                        clockLive: Bool,
                        railArmedSinceLoss: Bool) -> Origin? {
        if let current { return current }
        guard let lost, let sinceLoss, sinceLoss >= 0, !railArmedSinceLoss else { return nil }
        if clockLive {
            // Up to the Edit band, Left to the rail, a tab: the loss followed a directional press.
            guard let input = inputBeforeLoss, input.kind == .select,
                  input.ago >= 0, input.ago < selectToLossGrace else { return nil }
            return lost
        }
        return sinceLoss < lossGrace ? lost : nil
    }
}
