import Foundation

/// What Menu does on the mpv player, highest precedence first (P1 spec): an open panel takes it,
/// then an active step/scan is cancelled, then the up-next chip is dismissed, then a focused pill or
/// the bar hides, and only then the player exits. Pure, so the order has unit-test proof.
enum MenuPrecedence {
    enum Action: Equatable {
        case panel           // the presented panel handles it (it never reaches the player)
        case cancelMode      // stepping / scrubbing: nothing committed; scanning: back to the scan origin
        case dismissUpNext
        case hidePill        // hides the bar and clears the pill focus
        case hideBar
        case exit
    }

    static func resolve(panelOpen: Bool, modeActive: Bool, upNextShowing: Bool,
                        pillFocused: Bool, barUp: Bool) -> Action {
        if panelOpen { return .panel }
        if modeActive { return .cancelMode }
        if upNextShowing { return .dismissUpNext }
        if pillFocused { return .hidePill }
        if barUp { return .hideBar }
        return .exit
    }

    /// Every consumed action swallows its release too, so UIKit never sees a half press.
    /// BUG-165 (rc4 verdict): `.exit` used to let its release run up the responder chain while the
    /// cover's dismissal was in flight; an unhandled Menu at the end of that chain is "leave the
    /// app" on tvOS, which is what Steven's remote and the device rig both hit. Only `.panel` keeps
    /// its release (the presented panel owns the whole press).
    static func swallowsRelease(_ action: Action) -> Bool { action != .panel }
}

/// The Siri Remote's touch surface reports a light tap at touch-up even when the touch was a click
/// (any button, arrows included). The tap is ignored while any press is down and within 0.5 s of
/// the last press beginning or ending.
enum LightTapGuard {
    static let clickWindowSec: TimeInterval = 0.5

    static func allows(now: TimeInterval, lastPressUptime: TimeInterval, pressesDown: Int) -> Bool {
        pressesDown == 0 && now - lastPressUptime >= clickWindowSec
    }
}
