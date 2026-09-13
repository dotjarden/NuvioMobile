import Foundation
import CryptoKit

nonisolated struct LiveTVSource: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case m3u, xtream
        var id: String { rawValue }
        var title: String { self == .m3u ? "M3U playlist" : "Xtream Codes" }
    }
    var id = UUID()
    var name: String
    var kind: Kind
    var address: String
    var username = ""
    var password = ""
    var guideAddress = ""
}

nonisolated struct LiveTVChannel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let sourceID: UUID
    let name: String
    let group: String
    let logo: URL?
    let guideID: String
    let url: URL
    var headers: [String: String] = [:]
}

nonisolated struct LiveTVProgramme: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(channelID)|\(start.timeIntervalSince1970)|\(title)" }
    let channelID: String
    let title: String
    let summary: String
    let start: Date
    let end: Date
    func isCurrent(at date: Date) -> Bool { start <= date && date < end }
}

nonisolated enum LiveTVError: LocalizedError {
    case invalidURL, invalidPlaylist, invalidGuide, emptyChannels, response(Int), tooLarge, authentication, storage
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a complete HTTP or HTTPS address."
        case .invalidPlaylist: return "This address did not return an M3U playlist."
        case .invalidGuide: return "The programme guide could not be read as XMLTV."
        case .emptyChannels: return "This source did not return any playable live channels."
        case .response(let status): return "The provider returned HTTP \(status). Check the source details and try again."
        case .tooLarge: return "This provider response is too large to load safely. Try a smaller playlist or guide."
        case .authentication: return "The provider did not accept these account details."
        case .storage: return "The source could not be saved securely on this Apple TV."
        }
    }
}

nonisolated enum LiveTVURL {
    static func parse(_ value: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
}

nonisolated enum M3UParser {
    static func attributes(_ line: String) -> [String: String] {
        let regex = try! NSRegularExpression(pattern: #"([\w-]+)\s*=\s*"([^"]*)""#)
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).reduce(into: [:]) {
            $0[ns.substring(with: $1.range(at: 1)).lowercased()] = ns.substring(with: $1.range(at: 2))
        }
    }
    static func parse(_ text: String, source: LiveTVSource) throws -> [LiveTVChannel] {
        let text = text.replacingOccurrences(of: "\u{feff}", with: "")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw LiveTVError.invalidPlaylist }
        var channels: [LiveTVChannel] = [], seen = Set<String>()
        var attributes: [String: String] = [:], name = "", group = "", headers: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                attributes = self.attributes(line); headers = [:]; group = ""
                var quoted = false, comma: String.Index?
                for i in line.indices {
                    if line[i] == "\"" { quoted.toggle() }
                    if line[i] == "," && !quoted { comma = i; break }
                }
                name = comma.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? attributes["tvg-name"] ?? "Channel"
            } else if line.hasPrefix("#EXTGRP:") { group = String(line.dropFirst(8))
            } else if line.hasPrefix("#EXTVLCOPT:http-user-agent=") { headers["User-Agent"] = String(line.dropFirst("#EXTVLCOPT:http-user-agent=".count))
            } else if line.hasPrefix("#EXTVLCOPT:http-referrer=") { headers["Referer"] = String(line.dropFirst("#EXTVLCOPT:http-referrer=".count))
            } else if !line.isEmpty && !line.hasPrefix("#") {
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                defer { attributes = [:]; headers = [:]; name = ""; group = "" }
                guard let url = LiveTVURL.parse(parts[0], relativeTo: URL(string: source.address)) else { continue }
                if parts.count == 2 {
                    for item in URLComponents(string: "https://headers.invalid/?" + parts[1])?.queryItems ?? [] {
                        if ["user-agent", "referer", "origin"].contains(item.name.lowercased()), let value = item.value,
                           !value.contains("\r"), !value.contains("\n") { headers[item.name] = value }
                    }
                }
                // The full stream URL keeps duplicate guide IDs (HD/SD variants) distinct.
                let identity = LiveTVIdentity.digest(source.id.uuidString + "|" + url.absoluteString)
                guard seen.insert(identity).inserted else { continue }
                channels.append(LiveTVChannel(id: identity, sourceID: source.id,
                    name: name.isEmpty ? attributes["tvg-name"] ?? "Channel \(channels.count + 1)" : name,
                    group: attributes["group-title"] ?? (group.isEmpty ? "Other" : group),
                    logo: attributes["tvg-logo"].flatMap { LiveTVURL.parse($0) },
                    guideID: attributes["tvg-id"] ?? "", url: url, headers: headers))
            }
        }
        guard !channels.isEmpty else { throw LiveTVError.emptyChannels }
        return channels
    }
}

nonisolated final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programmes: [LiveTVProgramme] = []
    private var channel = "", title = "", summary = "", element = "", buffer = ""
    private var start: Date?, end: Date?
    private var inside = false
    private var isTV = false
    private let window: DateInterval
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyyMMddHHmmss Z"; return f
    }()
    init(now: Date = Date()) { window = DateInterval(start: now.addingTimeInterval(-86400), duration: 86400 * 8) }
    func parse(_ data: Data) throws -> [LiveTVProgramme] {
        programmes = []; isTV = false; inside = false
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse(), isTV else { throw LiveTVError.invalidGuide }
        return programmes.sorted { $0.start < $1.start }
    }
    private func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string.count == 14 ? string + " +0000" : string)
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "tv" { isTV = true }
        element = name; buffer = ""
        if name == "programme" { inside = true; channel = attributes["channel"] ?? ""; start = date(attributes["start"]); end = date(attributes["stop"]); title = ""; summary = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inside { buffer += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "title", title.isEmpty { title = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name == "desc", summary.isEmpty { summary = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
        if name == "programme" {
            if let start, let end, end > start, end > window.start, start < window.end, !channel.isEmpty {
                programmes.append(.init(channelID: channel, title: title.isEmpty ? "Untitled programme" : title, summary: summary, start: start, end: end))
            }
            inside = false
        }
        buffer = ""
    }
}

nonisolated enum LiveTVIdentity {
    static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
