import Foundation

/// Polish batch D3: the cached state a stream row's second fact line shows. `.instant` is a debrid
/// candidate that is a direct debrid link or a cached torrent (`StreamFacts.cached == true`);
/// `.notCached` is a debrid candidate that is not (`false`). A non-debrid stream has no state (nil).
nonisolated enum StreamRowCachedState: Equatable {
    case instant(provider: String?)
    case notCached
}

/// Polish batch D1/D3: the pure text rules behind a stream row's headline and fact lines. No views,
/// no Kotlin, no parser: `StreamRowModel.make` calls these once per stream (W3-16 F4) and the
/// results become plain values on the model; tests call them directly.
nonisolated enum StreamRowFacts {
    /// Most language names shown before the "+N" tail.
    static let maxLanguages = 3

    // MARK: - Headline and HDR mark

    /// The row headline for a vertical resolution. Thresholds floor to the step (never claim more
    /// than the file has) and equal the tier thresholds, so a headline always matches its header.
    /// Nil for an unknown or non-positive resolution: the row then shows its title.
    static func headline(forResolution resolution: Int?) -> String? {
        guard let resolution, resolution > 0 else { return nil }
        switch resolution {
        case 2160...: return "4K"
        case 1440...: return "1440p"
        case 1080...: return "1080p"
        case 720...: return "720p"
        default: return "SD"
        }
    }

    /// The HDR mark beside the headline: `StreamFacts.hdr` with every space as " · "
    /// ("DV HDR10" becomes "DV · HDR10"). Nil for nil or blank.
    static func hdrMark(_ hdr: String?) -> String? {
        guard let hdr else { return nil }
        let parts = hdr.split(separator: " ").map(String.init)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Fact line 1 (video)

    /// Fact line 1 terms: source type then codec, blanks dropped.
    static func videoFacts(sourceType: String?, codec: String?) -> [String] {
        [sourceType, codec].compactMap(clean)
    }

    // MARK: - Fact line 2 (audio, languages)

    /// Fact line 2 terms before the cached part: the audio label then the languages text.
    static func audioFacts(audio: String?, languages: [String], locale: Locale) -> [String] {
        [clean(audio), languagesText(languages, locale: locale)].compactMap { $0 }
    }

    /// "English, Spanish, French +2". Drops `unknown` and duplicates, maps `la` to "Latino" and
    /// `multi` to "Multi", names the rest in `locale` (first letter capitalised in that locale; the
    /// upper-cased code when the locale has no name), shows at most three and counts the rest.
    /// Nil when nothing is left.
    static func languagesText(_ codes: [String], locale: Locale) -> String? {
        var seen = Set<String>()
        var kept: [String] = []
        for raw in codes {
            let code = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !code.isEmpty, code != "unknown", seen.insert(code).inserted else { continue }
            kept.append(code)
        }
        guard !kept.isEmpty else { return nil }
        let names = kept.prefix(maxLanguages).map { name(forCode: $0, locale: locale) }
        let hidden = kept.count - names.count
        let joined = names.joined(separator: ", ")
        return hidden > 0 ? "\(joined) +\(hidden)" : joined
    }

    private static func name(forCode code: String, locale: Locale) -> String {
        switch code {
        case "la": return String(localized: "Latino")
        case "multi": return String(localized: "Multi")
        default:
            guard let name = locale.localizedString(forLanguageCode: code), !name.isEmpty else {
                return code.uppercased()
            }
            return name.prefix(1).uppercased(with: locale) + name.dropFirst()
        }
    }

    // MARK: - Cached part

    /// `cached` is `StreamFacts.cached`; `provider` is the debrid provider's short name when the
    /// stream carries a cached status (an empty name counts as none).
    static func cachedState(cached: Bool?, provider: String?) -> StreamRowCachedState? {
        guard let cached else { return nil }
        guard cached else { return .notCached }
        return .instant(provider: clean(provider))
    }

    /// The words of the cached part, without the symbol: "TB Instant", "Instant", "Not cached".
    static func cachedText(_ state: StreamRowCachedState) -> String {
        switch state {
        case .instant(let provider):
            if let provider = clean(provider) { return String(localized: "\(provider) Instant") }
            return String(localized: "Instant")
        case .notCached:
            return String(localized: "Not cached")
        }
    }

    /// The SF Symbol drawn before `cachedText`.
    static func cachedSymbol(_ state: StreamRowCachedState) -> String {
        switch state {
        case .instant: return "checkmark.circle"
        case .notCached: return "arrow.down.circle"
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
