import SwiftUI
import UIKit

// BUG-156 (a) (Steven, beta.19-rc4 verdict 2026-10-16): the strip's pop restore re-grabs its row when
// focus moves off it right after the pop, because on hardware the focus engine's own late
// restoration does exactly that (Batch A device pass, step 8). Until now the only way to tell that
// move from the viewer's own was its timing ("a second move is the viewer's"), which also made a
// late engine move look like the viewer's. This clock records the viewer's inputs, so the restore
// retires on the viewer's own press or swipe and re-grabs on anything else
// (`UncoverRestorePolicy`, `StageController.noteViewerInput`).
//
// One passive recognizer on the window, installed once by the first strip on screen and kept for
// the window's life: it sees every remote press as it BEGINS and every swipe once it has travelled,
// and recognizes nothing (the `HomeUpSwipeCatcher` configuration: no cancelling, no delaying,
// simultaneous with everything, no `require(toFail:)` anywhere).

/// See the file header.
@MainActor
final class ViewerInputClock {
    static let shared = ViewerInputClock()

    /// Posted on every recorded input; `object` is the clock.
    static let didRecord = Notification.Name("ViewerInputClock.didRecord")

    /// `ProcessInfo.systemUptime` of the last input, nil before any.
    private(set) var lastAt: TimeInterval?
    /// "up" / "down" / "left" / "right" / "select" / "menu" / "playPause" / "swipe".
    private(set) var lastKind = "-"
    /// The clock is installed on a window, so the absence of an input means something.
    var isLive: Bool { installedOn != nil }

    private weak var installedOn: UIWindow?
    private var recognizer: ViewerInputRecognizer?

    private init() {}

    func install(on window: UIWindow) {
        guard window !== installedOn else { return }
        if let installedOn, let recognizer { installedOn.removeGestureRecognizer(recognizer) }
        let created = ViewerInputRecognizer { [weak self] kind in
            self?.record(kind)
        }
        window.addGestureRecognizer(created)
        recognizer = created
        installedOn = window
    }

    func record(_ kind: String) {
        lastAt = ProcessInfo.processInfo.systemUptime
        lastKind = kind
        NotificationCenter.default.post(name: Self.didRecord, object: self)
    }

    /// The last input before `time` and how long before it, nil when the last input came later or
    /// there is none (the folder page's push-origin rule reads it at the strip's focus loss).
    func input(before time: TimeInterval) -> (kind: String, ago: TimeInterval)? {
        guard let lastAt, lastAt <= time else { return nil }
        return (lastKind, time - lastAt)
    }
}

/// Recognizes nothing. Reports a press when it BEGINS (before the focus engine's move has reached
/// SwiftUI, for most presses) and a swipe once the finger has travelled `swipeTravel` points, then
/// stays out of the running until the sequence ends.
final class ViewerInputRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Points of indirect-touch travel that make a swipe. Small next to the travel the focus engine
    /// needs for a move, so the stamp comes first; a thumb resting on the clickpad (Steven's hand on
    /// the Back press) never travels this far and never counts.
    private static let swipeTravel: CGFloat = 40

    private let onInput: (String) -> Void
    private var touchStart: CGPoint?
    private var swipeReported = false

    init(onInput: @escaping (String) -> Void) {
        self.onInput = onInput
        super.init(target: nil, action: nil)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        allowedPressTypes = [UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow,
                             .select, .menu, .playPause].map { NSNumber(value: $0.rawValue) }
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesBegan(presses, with: event)
        for press in presses {
            if let kind = Self.kind(of: press.type) { onInput(kind) }
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesEnded(presses, with: event)
        failIfIdle()
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesCancelled(presses, with: event)
        failIfIdle()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        touchStart = touches.first?.location(in: view)
        swipeReported = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard !swipeReported, let start = touchStart, let point = touches.first?.location(in: view) else { return }
        if hypot(point.x - start.x, point.y - start.y) >= Self.swipeTravel {
            swipeReported = true
            onInput("swipe")
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        touchStart = nil
        failIfIdle()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        touchStart = nil
        failIfIdle()
    }

    override func reset() {
        super.reset()
        touchStart = nil
        swipeReported = false
    }

    /// Back to `.possible` for the next sequence, never through `.began`.
    private func failIfIdle() {
        if state == .possible { state = .failed }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private static func kind(of type: UIPress.PressType) -> String? {
        switch type {
        case .upArrow: return "up"
        case .downArrow: return "down"
        case .leftArrow: return "left"
        case .rightArrow: return "right"
        case .select: return "select"
        case .menu: return "menu"
        case .playPause: return "playPause"
        default: return nil
        }
    }
}

/// Zero-size view that installs `ViewerInputClock` on its window (the strip mounts it).
struct ViewerInputClockInstaller: UIViewRepresentable {
    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { ViewerInputClock.shared.install(on: window) }
        }
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}
}
