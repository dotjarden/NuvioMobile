import AVKit
import SwiftUI
import UIKit

// Native AVKit transport owns the Settings entry point. Both engines present the same bottom
// drawer in a modal focus environment so underlying playback controls cannot steal remote input.
final class NativePlayerHostController: UIViewController {
    let playerVC = AVPlayerViewController()
    /// Asked to open a drawer tab from the native Settings menu. The owner
    /// builds the panel content and calls `present(panel:)`.
    var onOpenPanel: ((PlayerPanelTab) -> Void)?
    /// Fired after a presented panel has been dismissed (Back or programmatically).
    var onPanelClosed: (() -> Void)?
    /// Menu press hook (upstream 4026ec92 parity): return true to consume it — the up-next chip
    /// was dismissed — or false to let the press continue up to SwiftUI, whose `fullScreenCover`
    /// pops the player exactly as today.
    var onMenuPress: (() -> Bool)?
    private var pendingPanelTab: PlayerPanelTab?
    private var panelMenuWait: DispatchWorkItem?
    private var swallowMenuRelease = false
    private(set) var panelHost: PlayerPanelPresenting?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "player.native"
        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        installSettingsMenu()
    }

    func installSettingsMenu() {
        let actions = [PlayerPanelTab.audio, .subtitles, .playback, .info].map { tab in
            UIAction(title: tab.title) { [weak self] _ in
                guard let self, self.panelHost == nil else { return }
                self.openPanelAfterMenuDismissal(tab)
            }
        }
        playerVC.transportBarCustomMenuItems = [UIMenu(title: String(localized: "Settings"),
            image: UIImage(systemName: "slider.horizontal.3"), children: actions)]
    }

    private func openPanelAfterMenuDismissal(_ tab: PlayerPanelTab) {
        pendingPanelTab = tab
        panelMenuWait?.cancel()
        // A transition coordinator may be inherited from either enclosing SwiftUI cover and
        // may no longer accept completion handlers. Wait on the actual menu's dismissal instead.
        finishPendingPanelPresentation()
    }

    private func finishPendingPanelPresentation() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.view.window != nil, self.panelHost == nil,
                  let tab = self.pendingPanelTab else { return }
            if let menu = self.playerVC.presentedViewController ?? self.presentedViewController {
                if !menu.isBeingDismissed { menu.dismiss(animated: true) }
                self.finishPendingPanelPresentation()
                return
            }
            self.pendingPanelTab = nil
            self.onOpenPanel?(tab)
        }
        panelMenuWait = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    // This controller sits between AVPlayerViewController and the SwiftUI host in the focused
    // responder chain, so a Menu the system player did not consume (transport bar hidden) passes
    // through here on its way to the cover's default exit. Not while our panel or one of AVPVC's
    // own popovers is up — those own Menu themselves.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
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
        let restorePlaybackControls = playerVC.showsPlaybackControls
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        panel.onClosed = { [weak self] in
            self?.panelHost = nil
            self?.playerVC.showsPlaybackControls = restorePlaybackControls
            self?.onPanelClosed?()
        }
        panelHost = panel
        // The compact panel leaves more video visible. Hide AVKit's transport underneath it
        // so only one set of controls is on screen, then restore native interaction on Back.
        playerVC.showsPlaybackControls = false
        present(panel, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func closePanel(animated: Bool) {
        panelMenuWait?.cancel()
        pendingPanelTab = nil
        panelHost?.close(animated: animated)
    }
}

/// Type-erased handle on a presented panel host (the hosting controller itself is generic).
protocol PlayerPanelPresenting: AnyObject {
    func close(animated: Bool)
}

/// Hosts the SwiftUI panel over the player. Menu closes the panel (swallowed here so it never
/// reaches the SwiftUI `fullScreenCover` that would pop the whole player).
final class PlayerPanelHostController<Content: View>: UIHostingController<Content>, PlayerPanelPresenting {
    var onClosed: (() -> Void)?
    private var closing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "player.panel"
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


    func close(animated: Bool) {
        guard !closing else { return }
        closing = true
        let onClosed = onClosed
        dismiss(animated: animated && !UIAccessibility.isReduceMotionEnabled) { onClosed?() }
    }
}
