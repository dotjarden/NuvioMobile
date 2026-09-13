import Combine
import CoreImage
import Foundation
import SharedCore
import UIKit

/// Drives the "Remote Setup" section in Settings: runs `RemoteSetupServer`, feeds it a live
/// snapshot of addons / Home rows / key presence, surfaces incoming proposals as a confirm
/// alert, and — on confirm — applies the proposed state through the shared repos.
///
/// Nothing a browser sends is applied without an explicit confirmation on the TV.
@MainActor
final class RemoteSetupViewModel: ObservableObject {
    /// `http://<ip>:<port>` once the server is listening; nil while stopped.
    @Published private(set) var serverURL: String?
    @Published private(set) var qrImage: UIImage?
    @Published private(set) var startFailed = false
    /// Non-nil while a browser proposal awaits the user's decision (drives the alert).
    @Published var pendingChange: RemoteSetupServer.PendingChange?
    @Published private(set) var pendingSummary: String = ""

    var isRunning: Bool { serverURL != nil }

    /// True between `start()` and the server's bind completion. Blocks re-entrant starts so a
    /// Retry tap can't stack a second attempt (and a second set of watchers) on an unresolved
    /// one (ME-002).
    private var isStarting = false
    /// Bumped by `start()` and `stop()`; a bind completion from a superseded attempt is ignored
    /// so it can't republish the URL/QR after the user pressed Stop (HI-002/ME-002).
    private var startAttempt = 0

    private let server = RemoteSetupServer()
    private var addonWatcher: FlowWatcher?
    private var rowWatcher: FlowWatcher?
    private var tmdbWatcher: FlowWatcher?
    private var mdbListWatcher: FlowWatcher?
    private var badgeWatcher: FlowWatcher?
    private var applicationTask: Task<Void, Never>?
    private var stateReady = false

    // Cached snapshots (updated by the watchers, read when building state JSON + applying diffs).
    private var addons: [ManagedAddon] = []
    private var rows: [HomeCatalogSettingsItem] = []
    private var tmdbKeySet = false
    private var mdbListKeySet = false
    /// Source URLs of currently imported stream badge packs (shown read-only on the web page).
    private var badgePackUrls: [String] = []

    // MARK: - Lifecycle

    func start() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        startFailed = false
        startAttempt += 1
        let attempt = startAttempt

        server.onChangeProposed = { [weak self] change in
            Task { @MainActor in
                guard let self else { return }
                self.pendingSummary = self.summarize(change.proposal)
                self.pendingChange = change
            }
        }
        server.start { [weak self] port in
            Task { @MainActor in
                guard let self, attempt == self.startAttempt else { return }
                self.isStarting = false
                guard let port, let ip = DeviceIpAddress.current(),
                      let token = self.server.sessionToken else {
                    // Bind failed or no LAN address: tear the half-started server down so a
                    // Retry begins from a clean slate (ME-002).
                    self.server.stop()
                    self.startFailed = true
                    return
                }
                // Only now that the listener is actually ready: keep the TV awake (if tvOS idles
                // into the screensaver the app suspends and the server dies mid-edit) and start
                // feeding state. On failure the idle timer was never touched (ME-002).
                UIApplication.shared.isIdleTimerDisabled = true
                self.installWatchers()
                // The token is part of the URL — scanning the QR (or typing the short URL) is
                // what authorizes the browser session (HI-001).
                let url = "http://\(ip):\(port)/?t=\(token)"
                self.serverURL = url
                self.qrImage = Self.makeQrImage(from: url)
            }
        }
    }

    func stop() {
        startAttempt += 1
        isStarting = false
        startFailed = false
        UIApplication.shared.isIdleTimerDisabled = false
        applicationTask?.cancel()
        applicationTask = nil
        stateReady = false
        server.stop()
        serverURL = nil
        qrImage = nil
        pendingChange = nil
        cancelWatchers()
    }

    private func installWatchers() {
        cancelWatchers()
        addonWatcher = FlowWatcherKt.watch(AddonRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? AddonsUiState else { return }
            self.addons = state.addons
            self.pushState()
        }
        rowWatcher = FlowWatcherKt.watch(HomeCatalogSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? HomeCatalogSettingsUiState else { return }
            self.rows = state.items
            self.pushState()
        }
        tmdbWatcher = FlowWatcherKt.watch(TmdbSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? TmdbSettings else { return }
            self.tmdbKeySet = state.hasApiKey
            self.pushState()
        }
        mdbListWatcher = FlowWatcherKt.watch(MdbListSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? MdbListSettings else { return }
            self.mdbListKeySet = state.hasApiKey
            self.pushState()
        }
        badgeWatcher = FlowWatcherKt.watch(StreamBadgeSettingsRepository.shared.uiState) { [weak self] emitted in
            guard let self, let state = emitted as? StreamBadgeSettingsUiState else { return }
            self.badgePackUrls = state.rules.imports.map(\.sourceUrl)
            self.pushState()
        }
        AddonRepository.shared.initialize()
        TmdbSettingsRepository.shared.ensureLoaded()
        MdbListSettingsRepository.shared.ensureLoaded()
        StreamBadgeSettingsRepository.shared.ensureLoaded()
        stateReady = true
        pushState()
    }

    private func cancelWatchers() {
        addonWatcher?.cancel()
        rowWatcher?.cancel()
        tmdbWatcher?.cancel()
        mdbListWatcher?.cancel()
        badgeWatcher?.cancel()
        addonWatcher = nil
        rowWatcher = nil
        tmdbWatcher = nil
        mdbListWatcher = nil
        badgeWatcher = nil
    }

    // MARK: - Confirm / reject

    func confirmPending() {
        guard let change = pendingChange else { return }
        pendingChange = nil
        pushState()
        guard server.beginApplying(id: change.id) else { return }
        applicationTask = Task { [weak self] in
            guard let self else { return }
            let errors = await self.apply(change.proposal)
            guard !Task.isCancelled else { return }
            self.pushState()
            self.server.complete(id: change.id, errors: errors)
            self.applicationTask = nil
        }
    }

    func rejectPending() {
        guard let change = pendingChange else { return }
        server.reject(id: change.id)
        pendingChange = nil
    }

    // MARK: - State snapshot → server

    private struct StateAddon: Encodable {
        let url: String
        let name: String
        let description: String
        let enabled: Bool
    }
    private struct StateRow: Encodable {
        let key: String
        let title: String
        let enabled: Bool
        let isCollection: Bool
    }
    private struct StateSnapshot: Encodable {
        let deviceName: String
        let addons: [StateAddon]
        let rows: [StateRow]
        let tmdbKeySet: Bool
        let mdblistKeySet: Bool
        let badgePacks: [String]
    }

    private func pushState() {
        guard stateReady else { return }
        // Flow callbacks are queued on Main. Read through before serving/confirming so an
        // immediate browser refresh sees repository writes even before the next callback.
        addons = (AddonRepository.shared.uiState.value_ as? AddonsUiState)?.addons ?? addons
        rows = (HomeCatalogSettingsRepository.shared.uiState.value_ as? HomeCatalogSettingsUiState)?.items ?? rows
        tmdbKeySet = (TmdbSettingsRepository.shared.uiState.value_ as? TmdbSettings)?.hasApiKey ?? tmdbKeySet
        mdbListKeySet = (MdbListSettingsRepository.shared.uiState.value_ as? MdbListSettings)?.hasApiKey ?? mdbListKeySet
        badgePackUrls = (StreamBadgeSettingsRepository.shared.uiState.value_ as? StreamBadgeSettingsUiState)?.rules.imports.map(\.sourceUrl) ?? badgePackUrls
        let snapshot = StateSnapshot(
            deviceName: UIDevice.current.name,
            addons: addons.map {
                StateAddon(
                    url: $0.manifestUrl,
                    name: $0.displayTitle,
                    description: $0.manifest?.description_ ?? "",
                    enabled: $0.enabled
                )
            },
            rows: rows.map {
                StateRow(
                    key: $0.key,
                    title: $0.displayTitle,
                    enabled: $0.enabled,
                    isCollection: $0.isCollection
                )
            },
            tmdbKeySet: tmdbKeySet,
            mdblistKeySet: mdbListKeySet,
            badgePacks: badgePackUrls
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            server.updateState(data)
        }
    }

    // MARK: - Applying a confirmed proposal

    private func apply(_ proposal: RemoteSetupServer.Proposal) async -> [String] {
        var errors = await applyAddons(proposal)
        guard !Task.isCancelled else { return errors }
        applyRows(proposal)
        if let key = proposal.tmdbKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            TmdbSettingsRepository.shared.setApiKey(value: key)
            TmdbSettingsRepository.shared.setEnabled(value: true)
        }
        if let key = proposal.mdblistKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            MdbListSettingsRepository.shared.setApiKey(value: key)
            MdbListSettingsRepository.shared.setEnabled(value: true)
        }
        // Wait for each repository operation before reporting completion to the browser.
        for url in proposal.badgeUrls ?? [] {
            guard !Task.isCancelled else { break }
            let error: String? = await withCheckedContinuation { continuation in
                StreamBadgeSettingsRepository.shared.importStreamBadgeRulesFromUrl(url: url) { result, error in
                    let message: String?
                    if result is StreamBadgeImportResultSuccess { message = nil }
                    else { message = (result as? StreamBadgeImportResultError)?.message ?? error?.localizedDescription ?? "" }
                    continuation.resume(returning: message)
                }
            }
            if let error {
                errors.append("Badge pack: " + SettingsErrorMessage.readable(error, fallback: "Couldn't import. Check the URL and connection, then try again."))
            }
        }
        return errors
    }

    private var currentAddons: [ManagedAddon] {
        (AddonRepository.shared.uiState.value_ as? AddonsUiState)?.addons ?? addons
    }

    private func applyAddons(_ proposal: RemoteSetupServer.Proposal) async -> [String] {
        guard let proposed = proposal.addons else { return [] }
        let repo = AddonRepository.shared
        return await RemoteSetupAddonApplication.apply(proposed,
            snapshot: { self.currentAddons.map { .init(url: $0.manifestUrl, enabled: $0.enabled) } },
            install: { url in
                await withCheckedContinuation { continuation in
                    repo.addAddon(rawUrl: url) { result, error in
                        if result is AddAddonResultSuccess { continuation.resume(returning: nil) }
                        else { continuation.resume(returning: (result as? AddAddonResultError)?.message ?? error?.localizedDescription ?? "") }
                    }
                }
            },
            remove: { repo.removeAddon(manifestUrl: $0) },
            setEnabled: { repo.setAddonEnabled(manifestUrl: $0, enabled: $1) },
            move: { repo.moveAddon(fromIndex: Int32($0), toIndex: Int32($1)) })
    }

    private func applyRows(_ proposal: RemoteSetupServer.Proposal) {
        let repo = HomeCatalogSettingsRepository.shared
        let currentRows = (repo.uiState.value_ as? HomeCatalogSettingsUiState)?.items ?? rows

        if let disabledKeys = proposal.disabledRowKeys {
            let disabled = Set(disabledKeys)
            // Only touch rows the browser actually edited; newly installed catalogs keep defaults.
            let edited = Set(proposal.rowOrder ?? currentRows.map(\.key))
            for row in currentRows where edited.contains(row.key) {
                let shouldBeEnabled = !disabled.contains(row.key)
                if row.enabled != shouldBeEnabled {
                    repo.setEnabled(key: row.key, enabled: shouldBeEnabled)
                }
            }
        }

        if let order = proposal.rowOrder {
            var simulated = currentRows.map(\.key)
            let desired = order.filter { simulated.contains($0) }
            for targetIndex in desired.indices {
                guard let fromIndex = simulated.firstIndex(of: desired[targetIndex]),
                      fromIndex != targetIndex
                else { continue }
                repo.moveByIndex(fromIndex: Int32(fromIndex), toIndex: Int32(targetIndex))
                simulated.remove(at: fromIndex)
                simulated.insert(desired[targetIndex], at: targetIndex)
            }
        }
    }

    // MARK: - Alert summary

    private func summarize(_ proposal: RemoteSetupServer.Proposal) -> String {
        var parts: [String] = []

        if let proposed = proposal.addons {
            let currentUrls = Set(addons.map(\.manifestUrl))
            let proposedUrls = Set(proposed.map(\.url))
            let added = proposedUrls.subtracting(currentUrls).count
            let removed = currentUrls.subtracting(proposedUrls).count
            if added > 0 { parts.append(String(localized: "\(added) add-on\(added == 1 ? "" : "s") installed")) }
            if removed > 0 { parts.append(String(localized: "\(removed) add-on\(removed == 1 ? "" : "s") removed")) }
            let orderChanged = proposed.map(\.url).filter { currentUrls.contains($0) }
                != addons.map(\.manifestUrl).filter { proposedUrls.contains($0) }
            let togglesChanged = proposed.contains { entry in
                guard let enabled = entry.enabled,
                      let existing = addons.first(where: { $0.manifestUrl == entry.url })
                else { return false }
                return existing.enabled != enabled
            }
            if orderChanged || togglesChanged { parts.append(String(localized: "add-on settings changed")) }
        }

        if let order = proposal.rowOrder {
            let known = rows.map(\.key)
            let disabled = Set(proposal.disabledRowKeys ?? [])
            let orderChanged = order.filter { known.contains($0) } != known.filter { order.contains($0) }
            let togglesChanged = rows.contains { $0.enabled == disabled.contains($0.key) }
            if orderChanged || togglesChanged { parts.append(String(localized: "Home rows updated")) }
        }

        if proposal.tmdbKey?.isEmpty == false { parts.append(String(localized: "TMDB key set")) }
        if proposal.mdblistKey?.isEmpty == false { parts.append(String(localized: "MDBList key set")) }
        if let badgeCount = proposal.badgeUrls?.count, badgeCount > 0 {
            parts.append(String(localized: "\(badgeCount) badge pack\(badgeCount == 1 ? "" : "s") imported"))
        }

        return parts.isEmpty ? String(localized: "No changes detected.") : parts.joined(separator: " \u{00B7} ") + "."
    }

    // MARK: - QR

    private static func makeQrImage(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 14, y: 14))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    deinit {
        applicationTask?.cancel()
        server.stop()
        addonWatcher?.cancel()
        rowWatcher?.cancel()
        tmdbWatcher?.cancel()
        mdbListWatcher?.cancel()
        badgeWatcher?.cancel()
    }
}
