import Foundation

nonisolated struct LiveTVLoadResult: Sendable {
    let channels: [LiveTVChannel]
    let programmes: [LiveTVProgramme]
    let guideWarning: String?
}

actor LiveTVService {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()
    private func fetch(_ url: URL, limit: Int = 32 * 1024 * 1024) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse else { throw LiveTVError.response(0) }
        guard (200..<300).contains(response.statusCode) else { throw LiveTVError.response(response.statusCode) }
        guard response.expectedContentLength <= limit else { throw LiveTVError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count >= limit { throw LiveTVError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
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
        var programmes: [LiveTVProgramme] = [], warning: String?
        if let guideURL {
            do { programmes = try XMLTVParser().parse(try await fetch(guideURL, limit: 64 * 1024 * 1024)) }
            catch is CancellationError { throw CancellationError() }
            catch { warning = "Channels loaded, but the programme guide is unavailable. Check the guide address and refresh." }
        }
        return .init(channels: channels, programmes: programmes, guideWarning: warning)
    }
    private func endpoint(_ base: URL, path: String, source: LiveTVSource, action: String? = nil) throws -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "username", value: source.username), .init(name: "password", value: source.password)]
        if let action { components.queryItems?.append(.init(name: "action", value: action)) }
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
