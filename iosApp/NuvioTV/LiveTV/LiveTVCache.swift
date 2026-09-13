import CryptoKit
import Foundation
import Security

/// Purgeable per-profile cache, encrypted because channel addresses can contain credentials.
actor LiveTVCache {
    static let shared = LiveTVCache()
    struct Snapshot: Codable, Sendable {
        let fingerprint: String
        let date: Date
        let channels: [LiveTVChannel]
        let programmes: [UUID: [String: [LiveTVProgramme]]]
    }
    nonisolated static func fingerprint(_ sources: [LiveTVSource]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return LiveTVIdentity.digest(String(data: (try? encoder.encode(sources)) ?? Data(), encoding: .utf8) ?? "")
    }
    func read(profile: String, fingerprint: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(profile)),
              let key = try? key(profile),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(box, using: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: plaintext),
              snapshot.fingerprint == fingerprint,
              Date().timeIntervalSince(snapshot.date) < 7 * 86400 else { return nil }
        return snapshot
    }
    func write(_ snapshot: Snapshot, profile: String) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            let encrypted = try AES.GCM.seal(data, using: key(profile)).combined!
            let destination = file(profile)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encrypted.write(to: destination, options: .atomic)
        } catch { /* Cache failures must never prevent watching. */ }
    }
    func remove(profile: String) { try? FileManager.default.removeItem(at: file(profile)) }
    private func file(_ profile: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveTV").appendingPathComponent(LiveTVIdentity.digest(profile) + ".cache")
    }
    private func key(_ profile: String) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.nuvio.tv.livetv.cache", kSecAttrAccount as String: profile]
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw LiveTVError.storage }
        let key = SymmetricKey(size: .bits256)
        var insert = query
        insert[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw LiveTVError.storage }
        return key
    }
}
