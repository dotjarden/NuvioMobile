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
        // AVKit invokes UIAction before its menu finishes dismissing. Presenting here directly
        // loses the drawer to that transition. Wait for the actual presentation to finish.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelHost == nil else { return }
            let open = { [weak self] in
                guard let self, self.view.window != nil, self.panelHost == nil else { return }
                self.onOpenPanel?(tab)
            }
            if let menu = self.playerVC.presentedViewController ?? self.presentedViewController {
                if menu.isBeingDismissed, let transition = menu.transitionCoordinator {
                    transition.animate(alongsideTransition: nil) { _ in open() }
                } else {
                    menu.dismiss(animated: true, completion: open)
                }
            } else if let transition = self.playerVC.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { _ in open() }
            } else {
                open()
            }
        }
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
