import Foundation

/// One kind of Siri Remote input `ViewerInputClock` records (BUG-156 (a)). The raw value is the
/// token the `[StageStrip]` probe lines print (`input=select/50`).
nonisolated enum ViewerInputKind: String, Sendable {
    case up, down, left, right, select, menu, playPause, swipe
}

/// A recorded viewer input measured against a reference time: what it was and how long before
/// that time it came (`ViewerInputClock.input(before:)`, read by `FolderPushOrigin.resolve`).
nonisolated struct ViewerInput: Equatable, Sendable {
    let kind: ViewerInputKind
    let ago: TimeInterval
}
