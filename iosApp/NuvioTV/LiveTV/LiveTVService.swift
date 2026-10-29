import Foundation

nonisolated struct LiveTVLoadResult: Sendable {
    let channels: [LiveTVChannel]
    /// Programmes by guide ID, each list sorted by start. Grouped here, off the main actor.
    let programmes: [String: [LiveTVProgramme]]
    let guideWarning: String?
}

actor LiveTVService {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600  // provider guides can be hundreds of MB
        return URLSession(configuration: configuration)
    }()
    /// Downloads to a temporary file rather than appending the body byte by byte, which was the
    /// slowest part of loading a large playlist or guide. The caller owns (and removes) the file.
    private func download(_ url: URL, limit: Int) async throws -> URL {
        let (file, response) = try await session.download(from: url)
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("livetv-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: file, to: kept)
        do {
            guard let response = response as? HTTPURLResponse else { throw LiveTVError.response(0) }
            guard (200..<300).contains(response.statusCode) else { throw LiveTVError.response(response.statusCode) }
            let size = (try? kept.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= limit else { throw LiveTVError.tooLarge }
            try Task.checkCancellation()
            return kept
        } catch {
            try? FileManager.default.removeItem(at: kept)
            throw error
        }
    }
    private func fetch(_ url: URL, limit: Int = 64 * 1024 * 1024) async throws -> Data {
        let file = try await download(url, limit: limit)
        defer { try? FileManager.default.removeItem(at: file) }
        return try Data(contentsOf: file)
    }
    /// Provider guides for tens of thousands of channels are often hundreds of MB, and many are
    /// gzipped. The guide is parsed as a stream from disk, never held in memory whole.
    private func guide(_ url: URL, guideIDs: Set<String>) async throws -> [String: [LiveTVProgramme]] {
        var file = try await download(url, limit: 2 * 1024 * 1024 * 1024)
        defer { try? FileManager.default.removeItem(at: file) }
        if let unzipped = try LiveTVGzip.inflate(file) {
            try? FileManager.default.removeItem(at: file)
            file = unzipped
        }
        try Task.checkCancellation()
        return Dictionary(grouping: try XMLTVParser(guideIDs: guideIDs).parse(contentsOf: file), by: \.channelID)
    }
    func load(_ source: LiveTVSource, onChannels: @escaping @Sendable ([LiveTVChannel]) async -> Void = { _ in }) async throws -> LiveTVLoadResult {
        guard let base = LiveTVURL.parse(source.address) else { throw LiveTVError.invalidURL }
        var guideURL = LiveTVURL.parse(source.guideAddress)
        let channels: [LiveTVChannel]
        switch source.kind {
        case .m3u:
            let data = try await fetch(base)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw LiveTVError.invalidPlaylist }
            channels = try M3UParser.parse(text, source: source)
            if guideURL == nil, let first = text.components(separatedBy: .newlines).first {
                let attrs = M3UParser.attributes(first)
                guideURL = (attrs["x-tvg-url"] ?? attrs["url-tvg"]).flatMap { LiveTVURL.parse($0, relativeTo: base) }
            }
        case .xtream:
            channels = try await xtream(source, base: base)
            if guideURL == nil { guideURL = try endpoint(base, path: "xmltv.php", source: source) }
        }
        try Task.checkCancellation()
        await onChannels(channels)
        var programmes: [String: [LiveTVProgramme]] = [:], warning: String?
        if let guideURL {
            let ids = Set(channels.map(\.guideID).filter { !$0.isEmpty })
            do { programmes = try await guide(guideURL, guideIDs: ids) }
            catch is CancellationError { throw CancellationError() }
            catch {
                // Say why, without the address (it can carry credentials).
                let reason: String
                switch error {
                case let error as LiveTVError: reason = error.errorDescription ?? "It could not be read."
                case let error as URLError where error.code == .timedOut: reason = "The provider took too long to send it."
                case let error as URLError: reason = "The connection failed (\(error.code.rawValue))."
                default: reason = "It could not be read."
                }
                // Xtream channels fall back to per-channel now/next (`LiveTVStore.requestGuide`),
                // so a refused full guide is not worth a warning there.
                if source.kind == .m3u { warning = "Channels loaded, but the programme guide is unavailable. \(reason)" }
            }
        }
        return .init(channels: channels, programmes: programmes, guideWarning: warning)
    }
    /// Now/next for one Xtream channel (`get_short_epg`). Titles and descriptions arrive base64.
    func shortGuide(_ source: LiveTVSource, channel: LiveTVChannel) async throws -> [LiveTVProgramme] {
        guard let base = LiveTVURL.parse(source.address) else { throw LiveTVError.invalidURL }
        let streamID = channel.url.deletingPathExtension().lastPathComponent
        let data = try await fetch(endpoint(base, path: "player_api.php", source: source, action: "get_short_epg",
                                            extra: [.init(name: "stream_id", value: streamID), .init(name: "limit", value: "6")]),
                                   limit: 4 * 1024 * 1024)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let listings = root?["epg_listings"] as? [[String: Any]] ?? []
        func text(_ value: Any?) -> String {
            guard let raw = value as? String else { return "" }
            if let decoded = Data(base64Encoded: raw), let string = String(data: decoded, encoding: .utf8) { return string }
            return raw
        }
        return listings.compactMap { item -> LiveTVProgramme? in
            guard let start = string(item["start_timestamp"]).flatMap(Double.init),
                  let end = string(item["stop_timestamp"]).flatMap(Double.init), end > start else { return nil }
            let title = text(item["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            return LiveTVProgramme(channelID: LiveTVStore.guideKey(channel), title: title.isEmpty ? "Untitled programme" : title,
                                   summary: text(item["description"]).trimmingCharacters(in: .whitespacesAndNewlines),
                                   start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        }.sorted { $0.start < $1.start }
    }
    private func endpoint(_ base: URL, path: String, source: LiveTVSource, action: String? = nil, extra: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "username", value: source.username), .init(name: "password", value: source.password)]
        if let action { components.queryItems?.append(.init(name: "action", value: action)) }
        components.queryItems?.append(contentsOf: extra)
        guard let url = components.url else { throw LiveTVError.invalidURL }; return url
    }
    private func xtream(_ source: LiveTVSource, base: URL) async throws -> [LiveTVChannel] {
        let authData = try await fetch(endpoint(base, path: "player_api.php", source: source))
        let auth = try JSONSerialization.jsonObject(with: authData) as? [String: Any]
        let user = auth?["user_info"] as? [String: Any]
        guard string(user?["auth"]) == "1" else { throw LiveTVError.authentication }
        let formats = user?["allowed_output_formats"] as? [String] ?? ["m3u8"]
        let streamExtension = formats.contains("m3u8") ? "m3u8" : "ts"
        async let categoryRequest = fetch(endpoint(base, path: "player_api.php", source: source, action: "get_live_categories"))
        async let channelRequest = fetch(endpoint(base, path: "player_api.php", source: source, action: "get_live_streams"))
        let categoryData = try await categoryRequest
        let categories = (try JSONSerialization.jsonObject(with: categoryData)) as? [[String: Any]] ?? []
        var groups: [String: String] = [:]
        for item in categories { if let id = string(item["category_id"]) { groups[id] = string(item["category_name"]) } }
        let channelData = try await channelRequest
        let rows = try JSONSerialization.jsonObject(with: channelData) as? [[String: Any]] ?? []
        var seen = Set<String>()
        let channels = rows.compactMap { row -> LiveTVChannel? in
            guard let id = string(row["stream_id"]), !id.isEmpty, seen.insert(id).inserted else { return nil }
            // Encode each credential as one path segment, including embedded slash/percent signs.
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
            let segments = ["live", source.username, source.password, id + "." + streamExtension]
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.query = nil; components.fragment = nil
            components.percentEncodedPath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.percentEncodedPath = "/" + ([components.percentEncodedPath].filter { !$0.isEmpty } + segments).joined(separator: "/")
            guard let url = components.url else { return nil }
            return .init(id: LiveTVIdentity.digest(source.id.uuidString + "|" + id), sourceID: source.id,
                name: string(row["name"]) ?? "Channel \(id)", group: groups[string(row["category_id"]) ?? ""] ?? "Other",
                logo: string(row["stream_icon"]).flatMap { LiveTVURL.parse($0) },
                guideID: string(row["epg_channel_id"]) ?? "", url: url)
        }
        guard !channels.isEmpty else { throw LiveTVError.emptyChannels }
        return channels
    }
    private func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return (value as? NSNumber)?.stringValue
    }
}
