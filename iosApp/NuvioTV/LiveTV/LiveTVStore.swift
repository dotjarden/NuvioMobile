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
    func start() async { if !loaded { await refresh() } }
    func refresh() async {
        let token = UUID(); generation = token; loading = true; error = nil
        defer { if generation == token { loading = false } }
        let snapshot = sources
        var newChannels: [LiveTVChannel] = [], guides: [UUID: [String: [LiveTVProgramme]]] = [:], failures: [String] = []
        for source in snapshot {
            do {
                let result = try await service.load(source)
                guard generation == token, !Task.isCancelled else { return }
                newChannels += result.channels
                guides[source.id] = Dictionary(grouping: result.programmes, by: \.channelID)
                if let warning = result.guideWarning { failures.append("\(source.name): \(warning)") }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                // URLSession errors can contain credential-bearing URLs. Present curated text only.
                let message = (error as? LiveTVError)?.errorDescription ?? "Could not connect. Check the address, network, and provider account."
                failures.append("\(source.name): \(message)")
                newChannels += channels.filter { $0.sourceID == source.id }
                guides[source.id] = programmes[source.id]
            }
        }
        guard generation == token, !Task.isCancelled else { return }
        channels = newChannels; programmes = guides; loaded = true; refreshedAt = Date()
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    func save(_ source: LiveTVSource) async throws {
        var next = sources
        if let index = next.firstIndex(where: { $0.id == source.id }) { next[index] = source } else { next.append(source) }
        try LiveTVSecureStorage.write(next, profile: profile)
        sources = next; await refresh()
    }
    func remove(_ source: LiveTVSource) async throws {
        let next = sources.filter { $0.id != source.id }
        try LiveTVSecureStorage.write(next, profile: profile)
        sources = next
        let removed = Set(channels.filter { $0.sourceID == source.id }.map(\.id))
        favorites.subtract(removed); recent.removeAll { removed.contains($0) }; persistPreferences()
        channels.removeAll { $0.sourceID == source.id }; programmes[source.id] = nil
        await refresh()
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
