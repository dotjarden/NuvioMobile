import Foundation

/// When the native player shows the pause info card (P4 B16, spec §4.2 with [C-5]).
///
/// The card shows only when ALL hold: the viewer has been paused for `delaySec`; the system
/// transport bar is KNOWN hidden (a `visible=false` delegate callback arrived during this pause:
/// unknown counts as visible, so a delegate that never fires can never put the card over the bar);
/// the app panel is closed; the setting is on; the screen is in its playing phase; and no B17 item
/// rebuild is running (its transient pause is not a viewer pause). There is no "dismissed for the
/// rest of the pause" latch, as on mpv: a press hides the card and it comes back when the bar next
/// hides.
enum NativePauseCardRule {
    static let delaySec: Double = 1.5

    /// Kill switch for the device-pass outcome "tvOS 26's bar never hides while paused": set to
    /// false to drop the card on native (the screen keeps the code).
    static let supported = true

    static func visible(pausedSince: TimeInterval?, now: TimeInterval, barKnownHidden: Bool,
                        panelOpen: Bool, enabled: Bool, isPlayingPhase: Bool, isRebuilding: Bool) -> Bool {
        guard supported, enabled, isPlayingPhase, !isRebuilding, !panelOpen, barKnownHidden,
              let pausedSince else { return false }
        return now - pausedSince >= delaySec
    }
}
