import SwiftUI
import UIKit
import XCTest
@testable import NuvioTV

/// BUG-186: a close requested while the panel is still being presented used to be dropped by
/// UIKit, and the `closing` latch then swallowed every later Menu. These tests present a real
/// panel in a window and check that the close still ends in a dismissal.
@MainActor
final class PlayerPanelHostCloseTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeHost() -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .black
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        return host
    }

    /// Polls the main run loop until `condition` holds or `timeout` passes.
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func testCloseDuringPresentStillDismisses() {
        let host = makeHost()
        let panel = PlayerPanelHostController(rootView: Color.clear)
        panel.modalPresentationStyle = .overFullScreen
        panel.modalTransitionStyle = .crossDissolve
        var closedCount = 0
        panel.onClosed = { closedCount += 1 }

        host.present(panel, animated: true)
        // Menu inside the present animation.
        panel.close(animated: true)

        XCTAssertTrue(waitUntil(3) { host.presentedViewController == nil && closedCount > 0 },
                      "the panel must be dismissed even when closed mid-present")
        XCTAssertEqual(closedCount, 1, "onClosed fires once")
    }

    func testPanelCanCloseAgainAfterReopen() {
        let host = makeHost()
        let first = PlayerPanelHostController(rootView: Color.clear)
        first.modalPresentationStyle = .overFullScreen
        host.present(first, animated: false)
        XCTAssertTrue(waitUntil(2) { host.presentedViewController === first })
        first.close(animated: true)
        XCTAssertTrue(waitUntil(3) { host.presentedViewController == nil })

        // The latch is per controller, but a second close on the same controller after a completed
        // dismiss must not be stuck either (the flag resets in the completion).
        host.present(first, animated: false)
        XCTAssertTrue(waitUntil(2) { host.presentedViewController === first })
        first.close(animated: false)
        XCTAssertTrue(waitUntil(3) { host.presentedViewController == nil },
                      "a second close after a completed dismiss must dismiss again")
    }
}
