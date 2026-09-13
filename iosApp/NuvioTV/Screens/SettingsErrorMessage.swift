import Foundation

/// Preserve useful service messages while keeping transport dumps and request URLs off the TV.
nonisolated enum SettingsErrorMessage {
    static func readable(_ message: String, fallback: String) -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let diagnostics = ["nsurlerrordomain", "error domain=", "userinfo=", "exception", "stacktrace", "http://", "https://"]
        guard !text.isEmpty, text.count <= 240,
              !diagnostics.contains(where: lower.contains) else { return fallback }
        return text
    }
}
