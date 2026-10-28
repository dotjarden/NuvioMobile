import Foundation
import SharedCore

/// DEBUG harness knob (Direction C D9): `-debug.sourceListOpensWith FULL|BEST` pins the stream
/// picker's opening body for this launch, so the UI legs can run either body whatever the
/// fixture profile stores. Read-through only: the setting is profile-local (never synced), so
/// unlike `StreamAutoPlayModeDebugOverride` nothing is handed to a repository; the view model asks
/// `mode()` first. Never written. nil when absent, blank or unknown, and always nil in Release.
nonisolated enum StreamListOpensWithDebugOverride {
    static let debugKey = "debug.sourceListOpensWith"

    /// "FULL" / "FULL_LIST" -> .fullList; "BEST" / "BEST_PICK" -> .bestPick (trimmed, any case); else nil.
    static func parse(_ raw: String?) -> StreamListOpensWith? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return nil }
        switch text {
        case "FULL", "FULL_LIST": return .fullList
        case "BEST", "BEST_PICK": return .bestPick
        default: return nil
        }
    }

    /// The launch's override, or nil (and always nil in Release).
    static func mode(_ defaults: UserDefaults = .standard) -> StreamListOpensWith? {
        #if DEBUG
        return parse(defaults.string(forKey: debugKey))
        #else
        return nil
        #endif
    }
}
