import Combine
import SwiftUI
import UIKit

/// One owner for the native top bar. Per-tab SwiftUI toolbar preferences can be replayed by
/// inactive NavigationStacks during a push/pop, interrupting the system bar's transition.
/// Keep the native appearance and focus behavior, but settle visibility once after navigation.
struct TabBarPresentation: UIViewControllerRepresentable {
    let visibility: TabBarVisibility

    func makeUIViewController(context: Context) -> CoordinatorController {
        CoordinatorController(visibility: visibility,
            sidebar: SidebarChrome.isEnabled() || UserDefaults.standard.bool(forKey: "debug.sidebarSpike"))
    }

    func updateUIViewController(_ controller: CoordinatorController, context: Context) {
        controller.scheduleUpdate()
    }

    final class CoordinatorController: UIViewController {
        private var subscription: AnyCancellable?
        private var immersive = false
        private let sidebar: Bool
        private var updateScheduled = false
        private var waitingForTransition = false
        private weak var tabController: UITabBarController?

        init(visibility: TabBarVisibility, sidebar: Bool) {
            self.sidebar = sidebar
            super.init(nibName: nil, bundle: nil)
            subscription = visibility.$immersiveHidden.removeDuplicates().sink { [weak self] hidden in
                self?.immersive = hidden
                self?.scheduleUpdate()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleUpdate()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.applyVisibility()
            }
        }

        private func applyVisibility() {
            guard !waitingForTransition, let root = viewIfLoaded?.window?.rootViewController else { return }
            guard let controller = tabController ?? Self.findTabController(in: root) else { return }
            tabController = controller
            if let transition = controller.selectedViewController?.transitionCoordinator ?? controller.transitionCoordinator,
               transition.isAnimated {
                waitingForTransition = true
                let registered = transition.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.waitingForTransition = false
                    self?.scheduleUpdate()
                }
                if registered { return }
                waitingForTransition = false
            }

            let hidden = sidebar || immersive
            let wasHidden = controller.isTabBarHidden
            if wasHidden != hidden {
                // Do not start a second bar animation while NavigationStack is finishing one.
                controller.setTabBarHidden(hidden, animated: false)
            }
            // Hiding alone can leave tvOS focus in the invisible bar. Restore interaction with
            // visibility so returning to a root never leaves painted but unusable navigation.
            if controller.tabBar.isUserInteractionEnabled == hidden {
                controller.tabBar.isUserInteractionEnabled = !hidden
                controller.setNeedsFocusUpdate()
            }
            if wasHidden && !hidden {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                controller.setNeedsFocusUpdate()
            }
        }

        private static func findTabController(in controller: UIViewController) -> UITabBarController? {
            if let tab = controller as? UITabBarController { return tab }
            for child in controller.children {
                if let tab = findTabController(in: child) { return tab }
            }
            return nil
        }
    }
}
