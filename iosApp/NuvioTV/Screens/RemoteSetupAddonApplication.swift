import Foundation

/// Orders application around asynchronous installs. Injected repository operations keep the
/// actual apply sequence testable without touching accounts or installed providers.
@MainActor
enum RemoteSetupAddonApplication {
    typealias Entry = RemoteSetupServer.Proposal.AddonEntry

    static func apply(_ proposed: [Entry], snapshot: () -> [Entry],
                      install: (String) async -> String?, remove: (String) -> Void,
                      setEnabled: (String, Bool) -> Void, move: (Int, Int) -> Void) async -> [String] {
        let originalUrls = snapshot().map(\.url)
        var errors: [String] = []

        // Install first, sequentially. A failed replacement must not remove a working provider.
        for entry in proposed where !originalUrls.contains(entry.url) {
            guard !Task.isCancelled else { return errors }
            let error = await install(entry.url)
            if let error {
                errors.append("Add-on: " + SettingsErrorMessage.readable(error, fallback: "Couldn't install. Check the URL and connection, then try again."))
            }
        }
        guard !Task.isCancelled else { return errors }
        if errors.isEmpty {
            for url in originalUrls where !proposed.contains(where: { $0.url == url }) {
                remove(url)
            }
        } else if originalUrls.contains(where: { url in !proposed.contains(where: { $0.url == url }) }) {
            errors.append("Existing add-ons were kept because an installation failed.")
        }

        // New providers now exist. Apply their enabled state and the complete requested order.
        for entry in proposed {
            if let enabled = entry.enabled, snapshot().contains(where: { $0.url == entry.url }) {
                setEnabled(entry.url, enabled)
            }
        }
        let available = snapshot().map(\.url)
        let desired = proposed.map(\.url).filter { available.contains($0) }
        for (target, url) in desired.enumerated() {
            if let from = snapshot().firstIndex(where: { $0.url == url }), from != target {
                move(from, target)
            }
        }
        let actual = snapshot()
        let expected = proposed.map(\.url)
        if errors.isEmpty && (actual.map(\.url) != expected || proposed.contains(where: { entry in
            guard let enabled = entry.enabled else { return false }
            return actual.first(where: { $0.url == entry.url })?.enabled != enabled
        })) {
            errors.append("Add-on changes couldn't be saved for this profile. Check whether it uses the primary profile's add-ons.")
        }
        return errors
    }
}
