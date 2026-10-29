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
    // Compiled once: large playlists have tens of thousands of #EXTINF lines.
    private static let attributePattern = try! NSRegularExpression(pattern: #"([\w-]+)\s*=\s*"([^"]*)""#)
    static func attributes(_ line: String) -> [String: String] {
        let regex = attributePattern
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
    /// Guide IDs the loaded channels use. Provider guides often cover every channel they carry,
    /// so programmes for other channels are dropped while parsing instead of kept in memory.
    private let guideIDs: Set<String>?
    /// The guide pages from 3 hours back to 3 days ahead (`LiveTVGuideView`), so that is all we keep.
    static let window: (past: TimeInterval, future: TimeInterval) = (6 * 3600, 3 * 86400 + 3 * 3600)
    init(now: Date = Date(), guideIDs: Set<String>? = nil) {
        window = DateInterval(start: now.addingTimeInterval(-Self.window.past), duration: Self.window.past + Self.window.future)
        self.guideIDs = guideIDs
    }
    func parse(_ data: Data) throws -> [LiveTVProgramme] { try run(XMLParser(data: data)) }
    func parse(contentsOf file: URL) throws -> [LiveTVProgramme] {
        guard let parser = XMLParser(contentsOf: file) else { throw LiveTVError.invalidGuide }
        return try run(parser)
    }
    private func run(_ parser: XMLParser) throws -> [LiveTVProgramme] {
        programmes = []; isTV = false; inside = false
        parser.shouldResolveExternalEntities = false; parser.delegate = self
        guard parser.parse(), isTV else { throw LiveTVError.invalidGuide }
        return programmes.sorted { $0.start < $1.start }
    }
    private func date(_ string: String?) -> Date? { string.flatMap(Self.date) }
    /// XMLTV `yyyyMMddHHmmss [+-]HHMM` (offset optional, UTC when absent). Parsed by hand:
    /// DateFormatter took nearly all of the guide's load time on a large provider.
    static func date(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 14 else { return nil }
        func number(_ from: Int, _ length: Int) -> Int? {
            var value = 0
            for byte in bytes[from..<from + length] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2),
              let hour = number(8, 2), let minute = number(10, 2), let second = number(12, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var offset = 0
        if let sign = bytes.dropFirst(14).firstIndex(where: { $0 == 43 || $0 == 45 }), bytes.count >= sign + 5,
           let hours = number(sign + 1, 2), let minutes = number(sign + 3, 2) {
            offset = (hours * 3600 + minutes * 60) * (bytes[sign] == 45 ? -1 : 1)
        }
        // Days from the civil date (Howard Hinnant's algorithm), proleptic Gregorian, UTC.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        return Date(timeIntervalSince1970: TimeInterval(days * 86400 + hour * 3600 + minute * 60 + second - offset))
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "tv" { isTV = true }
        element = name; buffer = ""
        if name == "programme" {
            channel = attributes["channel"] ?? ""
            inside = guideIDs?.contains(channel) ?? true
            guard inside else { return }
            start = date(attributes["start"]); end = date(attributes["stop"]); title = ""; summary = ""
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inside { buffer += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inside else { return }
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

/// Gzip support for `.xml.gz` guides: strips the gzip header and inflates the raw DEFLATE body
/// with Foundation's zlib decompressor.
nonisolated enum LiveTVGzip {
    /// Returns a new file with the inflated guide, or nil when `file` is not gzip.
    static func inflate(_ file: URL) throws -> URL? {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b, data[data.startIndex + 2] == 8 else { return nil }
        let flags = data[data.startIndex + 3]
        var offset = 10
        if flags & 0x04 != 0 { offset += 2 + Int(data[data.startIndex + offset]) + Int(data[data.startIndex + offset + 1]) << 8 }
        if flags & 0x08 != 0 { while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < data.count, data[data.startIndex + offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count - 8 else { throw LiveTVError.invalidGuide }
        let body = data.subdata(in: data.startIndex + offset..<data.endIndex - 8)
        guard let inflated = try? (body as NSData).decompressed(using: .zlib) as Data else { throw LiveTVError.invalidGuide }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("livetv-\(UUID().uuidString).xml")
        try inflated.write(to: output)
        return output
    }
}
