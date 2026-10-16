import AVKit
import SwiftUI
import UIKit

// tvOS 26 removed AVPlayerViewController's classic swipe-down tabbed panel (Info · Subtitles ·
// Audio): custom info view controllers now render as a pill under the seek bar, and Subtitles /
// Audio became transport-bar popovers. Nuvio wants the classic top panel back (Infuse-style), so
// this file owns the two UIKit pieces that make an app-drawn panel possible ON TOP of the system
// player without giving up its transport bar, popovers, or contextual actions:
//
//  - `NativePlayerHostController` — container VC whose only child is the `AVPlayerViewController`.
//    Remote presses and swipes are dispatched to the FOCUSED view's responder chain; gesture
//    recognizers on any superview in that chain observe them too, so recognizers on this container's
//    view see the Down press / down swipe regardless of which internal AVPVC view holds focus.
//    (`contentOverlayView` is the wrong place — it sits below the controls, outside the chain.)
//  - `PlayerPanelHostController` — the presented panel. Presenting (`.overFullScreen`, clear
//    background) gives focus containment for free (AVPVC's focus environment goes inactive so the
//    transport bar can't react to the panel's presses), keeps the video rendering underneath, and
//    lets us swallow Menu deterministically so it closes the panel instead of popping the player.
final class NativePlayerHostController: UIViewController, UIGestureRecognizerDelegate, AVPlayerViewControllerDelegate {
    let playerVC = AVPlayerViewController()
    /// Asked to open the panel on a tab, optionally with one Playback column focused (Down press /
    /// down swipe → `.info`; the transport bar's Episodes / Sources items → `.playback`). The owner
    /// builds the panel content and calls `present(panel:)`.
    var onOpenPanel: ((PlayerPanelTab, PlaybackColumn?) -> Void)?
    /// The system transport bar is about to show (`true`) or hide (`false`). Reported from the
    /// AVPlayerViewController delegate (P4 B16, the native pause card's "bar known hidden" input).
    var onTransportBarVisibilityChange: ((Bool) -> Void)?
    /// Any remote press (Select, Play/Pause, the arrows, Menu), observed without consuming it
    /// (P4 B16: a press hides the pause card).
    var onAnyPress: (() -> Void)?
    /// Last reported transport-bar visibility, so the log line prints transitions only.
    private var lastBarVisible: Bool?
    /// Fired after a presented panel has been dismissed (any way: Menu, swipe up, programmatic).
    var onPanelClosed: (() -> Void)?
    /// Menu press hook (upstream 4026ec92 parity): return true to consume it — the up-next chip
    /// was dismissed — or false to let the press continue up to SwiftUI, whose `fullScreenCover`
    /// pops the player exactly as today.
    var onMenuPress: (() -> Bool)?
    private var swallowMenuRelease = false
    private(set) var panelHost: PlayerPanelPresenting?
    private var downPress: UITapGestureRecognizer!
    private var downSwipe: UISwipeGestureRecognizer!
    private var anyPress: UITapGestureRecognizer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "player.native"
        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)
        // P4 B16: transport-bar visibility for the native pause card (nothing else sets it).
        playerVC.delegate = self

        downPress = UITapGestureRecognizer(target: self, action: #selector(handleOpenGesture))
        downPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.downArrow.rawValue)]
        downPress.delegate = self
        downSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleOpenGesture))
        downSwipe.direction = .down
        downSwipe.delegate = self
        view.addGestureRecognizer(downPress)
        view.addGestureRecognizer(downSwipe)

        // P4 B16 [C-5]: presses reach `pressesBegan` here only when the focused AVPVC view did not
        // consume them (in practice Menu with the bar hidden), so Select, the arrows and
        // Play/Pause are observed with a simultaneous recogniser, like `downPress`, that consumes
        // nothing. Menu is left out of it on purpose and reported from `pressesBegan` instead: a
        // recogniser on Menu would sit in front of the player's Menu-to-exit path.
        anyPress = UITapGestureRecognizer(target: self, action: #selector(handleAnyPress))
        anyPress.allowedPressTypes = [UIPress.PressType.select, .playPause, .upArrow, .downArrow,
                                      .leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
        anyPress.cancelsTouchesInView = false
        anyPress.delegate = self
        view.addGestureRecognizer(anyPress)
    }

    @objc private func handleAnyPress() { onAnyPress?() }

    // MARK: AVPlayerViewControllerDelegate

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willTransitionToVisibilityOfTransportBar visible: Bool,
                              with coordinator: any AVPlayerViewControllerAnimationCoordinator) {
        if lastBarVisible != visible {
            lastBarVisible = visible
            // Kept in every build during P4 (transitions only): the device pass reads it to decide
            // whether tvOS 26's bar ever hides while paused (spec §4.2).
            print("[NativePlayer] bar visible=\(visible ? 1 : 0)")
        }
        onTransportBarVisibilityChange?(visible)
    }

    /// Recognize alongside AVPlayerViewController's own recognizers — never block the system player.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handleOpenGesture() {
        // Not while our panel is up, and not while the system player has one of ITS popovers
        // (Subtitles / Audio menus) presented — a Down there navigates the popover's rows and
        // must not also open the panel over it (`presentedViewController` reports ancestors'
        // presentations, not the child's, so check the player VC explicitly).
        guard panelHost == nil, presentedViewController == nil,
              playerVC.presentedViewController == nil else { return }
        onOpenPanel?(.info, nil)
    }

    /// Opens the panel on `tab` with `column` focused (the transport bar's Episodes / Sources menu
    /// items). Same guards as the Down press: never over our own panel or a system popover.
    func openPanel(tab: PlayerPanelTab, column: PlaybackColumn?) {
        guard panelHost == nil, presentedViewController == nil,
              playerVC.presentedViewController == nil else { return }
        onOpenPanel?(tab, column)
    }

    // This controller sits between AVPlayerViewController and the SwiftUI host in the focused
    // responder chain, so a Menu the system player did not consume (transport bar hidden) passes
    // through here on its way to the cover's default exit. Not while our panel or one of AVPVC's
    // own popovers is up — those own Menu themselves (same guard as `handleOpenGesture`).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // P4 B16: Menu is the one press the any-press recogniser leaves out; report it here
        // (observation only, the handling below is unchanged).
        if presses.contains(where: { $0.type == .menu }) { onAnyPress?() }
        if presses.contains(where: { $0.type == .menu }),
           panelHost == nil, presentedViewController == nil, playerVC.presentedViewController == nil,
           onMenuPress?() == true {
            swallowMenuRelease = true
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Swallow the matching Menu release too, so nothing above sees a half press.
        if swallowMenuRelease, presses.contains(where: { $0.type == .menu }) {
            swallowMenuRelease = false
            return
        }
        super.pressesEnded(presses, with: event)
    }

    /// Present the panel over the live player. `crossDissolve` fades the host; the panel content
    /// animates its own slide-in. Reduce Motion → no animation at all.
    func present<Content: View>(panel: PlayerPanelHostController<Content>) {
        guard panelHost == nil, presentedViewController == nil else { return }
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        panel.onClosed = { [weak self] in
            self?.panelHost = nil
            self?.onPanelClosed?()
        }
        panelHost = panel
        present(panel, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func closePanel(animated: Bool) {
        panelHost?.close(animated: animated)
    }
}

/// Type-erased handle on a presented panel host (the hosting controller itself is generic).
protocol PlayerPanelPresenting: AnyObject {
    func close(animated: Bool)
}

/// Hosts the SwiftUI panel over the player. Menu closes the panel (swallowed here so it never
/// reaches the SwiftUI `fullScreenCover` that would pop the whole player); swipe up also closes.
final class PlayerPanelHostController<Content: View>: UIHostingController<Content>, PlayerPanelPresenting {
    var onClosed: (() -> Void)?
    private var closing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "player.panel"
        let up = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        up.direction = .up
        view.addGestureRecognizer(up)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            close(animated: true)
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Swallow the matching Menu release too, so nothing below sees a half press.
        if presses.contains(where: { $0.type == .menu }) { return }
        super.pressesEnded(presses, with: event)
    }

    @objc private func handleSwipeUp() { close(animated: true) }

    func close(animated: Bool) {
        guard !closing else { return }
        closing = true
        let onClosed = onClosed
        dismiss(animated: animated && !UIAccessibility.isReduceMotionEnabled) { onClosed?() }
    }
}
