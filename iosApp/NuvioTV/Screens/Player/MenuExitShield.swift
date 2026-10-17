import UIKit

/// BUG-165 (Steven, beta.19-rc4 verdict 2026-10-16, on video 6:18–6:28 with a real Siri Remote):
/// leaving the mpv player sent the app to the tvOS home screen; four seconds later NuvioTV resumed
/// on the source list that had been under the player (suspended, not killed). Both of his plays
/// started from the Continue Watching hold menu, so the player cover sat over the stream picker
/// over Home with no Detail page in the stack. The device rig had ejected the app the same way four
/// times on 2026-10-15 (P3-F8) with its own Menu presses.
///
/// The mechanism this guards against: a Menu press that reaches the END of the responder chain
/// unhandled while the player cover is going away. tvOS treats an unhandled Menu as "leave the
/// app". The player consumes the Menu that exits it (`MenuPrecedence.exit`), but its release used
/// to run up the chain (`swallowsRelease(.exit)` was false), and any press that lands while the
/// cover's dismissal is still in flight finds the player's view gone, the cover's own Menu
/// recogniser disabled (`gateCoverMenuTap`) and nothing under it that answers a Menu.
///
/// The shield is one press-only `UITapGestureRecognizer` on the window that is ENABLED only
/// between the exit decision (`arm`) and the end of the cover's dismissal (`disarm`, from the
/// player screen's `onDisappear`, or `maxArmedSeconds` as the safety net). A recognised Menu is
/// claimed by the recogniser, so the responder chain sees `pressesCancelled` and the press is never
/// unhandled: it cannot leave the app. Outside that window the recogniser is disabled and nothing
/// changes. The SwiftUI cover dismisses on Menu through exactly this kind of recogniser on its
/// `UITransitionView`, which is why a recognised press pre-empts the chain.
@MainActor
final class MenuExitShield: NSObject, UIGestureRecognizerDelegate {
    static let shared = MenuExitShield()

    /// The armed window's ceiling: a host that never calls `disarm` (no `MPVPlayerScreen`) gets
    /// its Menu presses back after this.
    nonisolated static let maxArmedSeconds: TimeInterval = 2.5

    private weak var installedOn: UIWindow?
    private var recognizer: UITapGestureRecognizer?
    private var armedAt: TimeInterval?
    private var disarmWork: DispatchWorkItem?
    /// Presses the shield claimed since launch (the `[MenuProbe]` lines carry the count).
    private(set) var swallowedCount = 0

    /// Idempotent per window. Called from the player controller once it has a window.
    func install(on window: UIWindow) {
        guard window !== installedOn else { return }
        if let old = recognizer, let oldWindow = installedOn {
            oldWindow.removeGestureRecognizer(old)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMenu(_:)))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        // Press-only: a light tap of the Siri Remote surface must never be read as a Menu.
        tap.allowedTouchTypes = []
        tap.cancelsTouchesInView = false
        tap.delegate = self
        tap.isEnabled = false
        window.addGestureRecognizer(tap)
        recognizer = tap
        installedOn = window
    }

    var isArmed: Bool { armedAt != nil }

    /// The player decided to exit on this Menu press. From here until `disarm`, every Menu press
    /// the window sees is claimed.
    func arm(reason: String) {
        #if DEBUG
        // A/B knob for the device and the simulator leg: `-debug.menuExitShieldOff YES` leaves every
        // Menu to the responder chain, so a run can show what the shield changes.
        if UserDefaults.standard.bool(forKey: "debug.menuExitShieldOff") {
            NSLog("[MenuProbe] shield off (debug knob) reason=%@", reason)
            return
        }
        #endif
        let now = ProcessInfo.processInfo.systemUptime
        armedAt = now
        recognizer?.isEnabled = true
        disarmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disarm(reason: "timeout") }
        disarmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxArmedSeconds, execute: work)
        NSLog("[MenuProbe] shield armed reason=%@ installed=%d", reason, recognizer == nil ? 0 : 1)
    }

    /// The cover is gone (or the ceiling passed): Menu presses go back to the responder chain.
    func disarm(reason: String) {
        guard let armedAt else { return }
        let held = ProcessInfo.processInfo.systemUptime - armedAt
        self.armedAt = nil
        disarmWork?.cancel()
        disarmWork = nil
        recognizer?.isEnabled = false
        NSLog("[MenuProbe] shield disarmed reason=%@ held=%dms swallowed=%d", reason, Int(held * 1000), swallowedCount)
    }

    /// The rule decides BEFORE a press is claimed (review r2 P3-4): a Menu that begins after the
    /// ceiling but before the disarm timer fired is left to the responder chain.
    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            let claims = MenuExitShieldRule.claims(armedAt: armedAt, now: ProcessInfo.processInfo.systemUptime)
            if !claims { disarm(reason: "ceiling") }
            return claims
        }
    }

    @objc private func handleMenu(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        swallowedCount += 1
        let age = armedAt.map { Int((ProcessInfo.processInfo.systemUptime - $0) * 1000) } ?? -1
        NSLog("[MenuProbe] shield swallowed menu n=%d age=%dms", swallowedCount, age)
    }
}

/// The pure half of `MenuExitShield`: whether a Menu press at `now` is inside the armed window.
nonisolated enum MenuExitShieldRule {
    static func claims(armedAt: TimeInterval?, now: TimeInterval,
                       ceiling: TimeInterval = MenuExitShield.maxArmedSeconds) -> Bool {
        guard let armedAt else { return false }
        let age = now - armedAt
        return age >= 0 && age < ceiling
    }
}
