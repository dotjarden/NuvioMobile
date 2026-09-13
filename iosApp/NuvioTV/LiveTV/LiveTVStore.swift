import Foundation
import Combine
import Security

/// Credentials and credential-bearing playlist URLs live in the device Keychain, scoped to the
/// active Nuvio profile. They never enter account sync, debug logs, or UserDefaults.
enum LiveTVSecureStorage {
    static func read(profile: String) throws -> [LiveTVSource] {
        var query = base(profile); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw LiveTVError.storage }
        return try JSONDecoder().decode([LiveTVSource].self, from: data)
    }
    static func write(_ sources: [LiveTVSource], profile: String) throws {
        let data = try JSONEncoder().encode(sources), query = base(profile)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw LiveTVError.storage }
        } else if status != errSecSuccess { throw LiveTVError.storage }
    }
    private static func base(_ profile: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.nuvio.tv.livetv", kSecAttrAccount as String: profile]
    }
}

@MainActor final class LiveTVStore: ObservableObject {
    @Published private(set) var sources: [LiveTVSource] = []
    @Published private(set) var channels: [LiveTVChannel] = []
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var favorites = Set<String>()
    @Published private(set) var recent: [String] = []
    @Published private(set) var programmes: [UUID: [String: [LiveTVProgramme]]] = [:]
    @Published private(set) var refreshedAt: Date?
    private var loaded = false
    private var generation = UUID()
    private let service = LiveTVService()
    let profile: String
    init(profile: String) {
        self.profile = profile
        do { sources = try LiveTVSecureStorage.read(profile: profile) }
        catch { self.error = "Saved Live TV sources could not be read. Try again after unlocking this Apple TV." }
        favorites = Set(UserDefaults.standard.stringArray(forKey: "livetv.favorites.\(profile)") ?? [])
        recent = UserDefaults.standard.stringArray(forKey: "livetv.recent.\(profile)") ?? []
    }
    var groups: [String] { Array(Set(channels.map(\.group))).filter { !["All channels", "Favorites", "Recent"].contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var refreshTask: Task<Void, Never>?
    func start() async {
        guard !loading else { return }
        if loaded, let refreshedAt, Date().timeIntervalSince(refreshedAt) < 15 * 60 { return }
        let fingerprint = LiveTVCache.fingerprint(sources)
        if let cached = await LiveTVCache.shared.read(profile: profile, fingerprint: fingerprint),
           fingerprint == LiveTVCache.fingerprint(sources) {
            channels = cached.channels; programmes = cached.programmes; refreshedAt = cached.date
            if Date().timeIntervalSince(cached.date) < 15 * 60 { loaded = true; return }
        }
        await refresh()
    }
    func refresh() async {
        let token = UUID(); generation = token; loading = true; error = nil
        defer { if generation == token { loading = false } }
        let snapshot = sources
        let service = service
        var failures: [String] = []
        await withTaskGroup(of: (LiveTVSource, LiveTVLoadResult?, String?).self) { group in
            var pending = snapshot.makeIterator()
            func enqueue(_ source: LiveTVSource) {
                group.addTask {
                    do {
                        let result = try await service.load(source) { channels in
                            await self.receive(channels, from: source.id, generation: token)
                        }
                        return (source, result, nil)
                    } catch {
                        let message = (error as? LiveTVError)?.errorDescription ?? "Could not connect. Check the address, network, and provider account."
                        return (source, nil, message)
                    }
                }
            }
            // Bound simultaneous provider requests; publish each playlist before its guide completes.
            for _ in 0..<3 { if let source = pending.next() { enqueue(source) } }
            for await (source, result, failure) in group {
                guard generation == token, !Task.isCancelled else { group.cancelAll(); return }
                if let result {
                    if result.guideWarning == nil {
                        programmes[source.id] = Dictionary(grouping: result.programmes, by: \.channelID)
                    }
                    if let warning = result.guideWarning { failures.append("\(source.name): \(warning)") }
                } else if let failure { failures.append("\(source.name): \(failure)") }
                if let source = pending.next() { enqueue(source) }
            }
        }
        guard generation == token, !Task.isCancelled else { return }
        loaded = failures.isEmpty; refreshedAt = Date()
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
        if failures.isEmpty {
            await LiveTVCache.shared.write(.init(fingerprint: LiveTVCache.fingerprint(snapshot), date: Date(),
                channels: channels, programmes: programmes), profile: profile)
        }
    }
    private func receive(_ incoming: [LiveTVChannel], from source: UUID, generation token: UUID) {
        guard generation == token else { return }
        let bySource = Dictionary(grouping: channels.filter { $0.sourceID != source } + incoming, by: \.sourceID)
        channels = sources.flatMap { bySource[$0.id] ?? [] }
    }
    private func refreshInBackground() {
        generation = UUID()
        loaded = false
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }
    func save(_ source: LiveTVSource) async throws {
        var next = sources
        if let index = next.firstIndex(where: { $0.id == source.id }) { next[index] = source } else { next.append(source) }
        try LiveTVSecureStorage.write(next, profile: profile)
        sources = next
        // Source edits invalidate cached signed URLs immediately. The editor can dismiss now.
        await LiveTVCache.shared.remove(profile: profile)
        refreshInBackground()
    }
    func remove(_ source: LiveTVSource) async throws {
        let next = sources.filter { $0.id != source.id }
        try LiveTVSecureStorage.write(next, profile: profile)
        sources = next
        let removed = Set(channels.filter { $0.sourceID == source.id }.map(\.id))
        favorites.subtract(removed); recent.removeAll { removed.contains($0) }; persistPreferences()
        channels.removeAll { $0.sourceID == source.id }; programmes[source.id] = nil
        await LiveTVCache.shared.remove(profile: profile)
        refreshInBackground()
    }
    func toggleFavorite(_ channel: LiveTVChannel) {
        if favorites.contains(channel.id) { favorites.remove(channel.id) } else { favorites.insert(channel.id) }; persistPreferences()
    }
    func watched(_ channel: LiveTVChannel) {
        recent.removeAll { $0 == channel.id }; recent.insert(channel.id, at: 0); recent = Array(recent.prefix(30)); persistPreferences()
    }
    func schedule(for channel: LiveTVChannel, after date: Date = Date()) -> [LiveTVProgramme] {
        (programmes[channel.sourceID]?[channel.guideID] ?? []).filter { $0.end > date }
    }
    private func persistPreferences() {
        // IDs from M3U can contain URLs. Persist opaque SHA256 keys instead of those URLs.
        UserDefaults.standard.set(Array(favorites), forKey: "livetv.favorites.\(profile)")
        UserDefaults.standard.set(recent, forKey: "livetv.recent.\(profile)")
    }
}
