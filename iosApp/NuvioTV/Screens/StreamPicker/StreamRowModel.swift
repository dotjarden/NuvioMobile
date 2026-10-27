import Foundation
import SharedCore

// MARK: - Row model (W3-16)

/// What shapes a prebuilt stream row beyond the stream itself: the shared badge settings and the
/// "- <Provider> Instant" suffix. Part of the row model's identity (`StreamRowModel.==` compares
/// the values it produced), and of `StreamsViewModel.Group`, so a settings flip rebuilds the rows.
nonisolated struct StreamRowDisplay: Equatable {
    /// The file-size chip is on (`showFileSizeBadges`; the row still needs a size to show it).
    var showFileSize = true
    /// Badges above the title instead of below it.
    var badgesOnTop = false
    /// The inline add-on label (logo + name) on the row's first line.
    var showAddonLogo = false
    /// The Instant suffix on debrid-cached rows (debrid resolution on, no custom name template).
    var instantSuffix = false
}

/// An external player the row's long-press menu can offer. A plain-Swift copy of the Kotlin
/// `ExternalPlayerApp`, so the menu's list takes part in `StreamRowModel.==`.
nonisolated struct StreamRowPlayer: Equatable {
    let id: String
    let name: String
}

/// W3-16 (F1/F4, BUG-207): everything a stream row shows, as one plain value. Built in two steps:
///
/// - `make(stream:key:display:)`, once per stream in `StreamsViewModel.apply(_:)`: the focus key,
///   the title (with the Instant suffix), the description, the badges, the size, the add-on column,
///   the YouTube flag and the playback key (one SHA-256 pair, so a row body never recomputes it);
/// - `applying(...)`, in the picker's body: the four things only the picker knows — the debrid
///   spinner, the "Failed recently" caption, and the external players with their default.
///
/// `StreamRowView` is `Equatable` over this value, so a row whose model is unchanged is never
/// re-evaluated when a sibling's focus, the scroll or the list's state moves. Every field below is
/// compared: dropping one would freeze that part of a row (the spinner, the rejected caption, the
/// badge settings, the Instant-suffix title, the player list with its default).
nonisolated struct StreamRowModel: Equatable, Identifiable {
    /// The focus key (`"<groupId>#<identity>"`), stable across republishes.
    let key: String
    /// The row title. With a `headline` it is the plain stream label (the cached glyph carries the
    /// Instant state); without one it keeps the "- <Provider> Instant" suffix on a cached torrent row.
    let title: String
    /// The add-on's description (release name), nil when empty or absent.
    let description: String?
    let badges: [StreamBadgeInfo]
    /// The size text's bytes (`StreamFacts.sizeBytes`); nil when File Size Badges is off or the
    /// stream has no size.
    let sizeBytes: Int64?
    let badgesOnTop: Bool
    /// The inline add-on label (logo + name) on line 1 is drawn ("Show Add-on Logo").
    let showsAddonColumn: Bool
    let addonName: String
    /// The add-on's logo URL, nil when it has none.
    let addonLogo: String?
    /// The add-on gave only a YouTube video id: the row says so and resolves it on the device.
    let isYouTube: Bool
    /// `StreamItem.playbackStreamKey`: what `RejectedStreamLinks` stores.
    let playbackKey: String
    /// polish D4: `StreamFacts.resolution`, drives the tier. Nil when the release names none.
    let resolution: Int?
    /// D1: "4K" / "1440p" / "1080p" / "720p" / "SD"; nil shows `title` on line 1 instead.
    let headline: String?
    /// D1: the HDR mark beside the headline ("DV · HDR10"); nil when `headline` is nil.
    let hdrMark: String?
    /// D1: fact line 1 terms (source type, codec).
    let videoFacts: [String]
    /// D1: fact line 2 terms before the cached part (audio, languages).
    let audioFacts: [String]
    /// D3: the cached part of fact line 2; already nil when the title carries the Instant suffix.
    let cachedState: StreamRowCachedState?

    /// This row's debrid / YouTube resolve is in flight (the spinner beside the title).
    var isResolving = false
    /// The link failed recently for this title ("Failed recently" caption).
    var failedRecently = false
    /// The external players the long-press menu offers (empty = no menu).
    var players: [StreamRowPlayer] = []
    /// The validated default external player's id, nil when the built-in player is the default.
    var defaultPlayerId: String?

    var id: String { key }

    /// The badge row is drawn (the size moved to line 1 and no longer makes one).
    var hasBadgeRow: Bool { !badges.isEmpty }
    /// Fact line 1 (source type, codec) is drawn.
    var hasVideoLine: Bool { !videoFacts.isEmpty }
    /// Fact line 2 (audio, languages, cached state) is drawn.
    var hasAudioLine: Bool { !audioFacts.isEmpty || cachedState != nil }

    /// The part the picker's own state decides (spinner, rejected caption, players).
    func applying(isResolving: Bool, failedRecently: Bool, players: [StreamRowPlayer],
                  defaultPlayerId: String?) -> StreamRowModel {
        var copy = self
        copy.isResolving = isResolving
        copy.failedRecently = failedRecently
        copy.players = players
        copy.defaultPlayerId = defaultPlayerId
        return copy
    }

    /// Builds the static part of a row. `providerLabel` names the debrid provider for the Instant
    /// suffix (injected so a test needs no provider catalog).
    @MainActor
    static func make(
        stream: StreamItem,
        key: String,
        display: StreamRowDisplay,
        providerLabel: (StreamDebridCacheStatus) -> String = StreamRowModel.debridProviderLabel
    ) -> StreamRowModel {
        // Kotlin nullable Strings surface as non-optional Swift String, so widen explicitly.
        let desc: String? = stream.description_
        let logo: String? = stream.addonLogo
        let badges: [StreamBadge] = stream.badges
        // The parser runs once per stream, here, never in a body (W3-16 F4); every derived field
        // below comes from this one value.
        let facts = StreamFactsParser.shared.parse(stream: stream)
        let resolution: Int? = facts.resolution.map { Int($0.intValue) }
        let headline = StreamRowFacts.headline(forResolution: resolution)
        // Exactly one of the title and the glyph says "Instant" (D3). With a headline the title is
        // the plain label and the glyph carries it; without one the title keeps the suffix, and the
        // glyph is dropped when the suffix was appended.
        let plainTitle: String = stream.streamLabel
        let fullTitle = title(for: stream, instantSuffix: display.instantSuffix, providerLabel: providerLabel)
        let titleCarriesInstant = headline == nil && fullTitle != plainTitle
        var provider: String?
        if let status = stream.debridCacheStatus, status.state == .cached {
            provider = providerLabel(status)
        }
        let cached: Bool? = facts.cached?.boolValue
        let sizeBytes: Int64? = display.showFileSize ? facts.sizeBytes?.int64Value : nil
        let languages: [String] = facts.languages
        return StreamRowModel(
            key: key,
            title: headline != nil ? plainTitle : fullTitle,
            description: (desc ?? "").isEmpty ? nil : desc,
            badges: badges.map { StreamBadgeInfo($0) },
            sizeBytes: sizeBytes,
            badgesOnTop: display.badgesOnTop,
            showsAddonColumn: display.showAddonLogo,
            addonName: stream.addonName,
            addonLogo: (logo ?? "").isEmpty ? nil : logo,
            isYouTube: StreamPickerView.isYouTubeResolved(stream),
            playbackKey: stream.playbackStreamKey,
            resolution: resolution,
            headline: headline,
            hdrMark: headline == nil ? nil : StreamRowFacts.hdrMark(facts.hdr),
            videoFacts: StreamRowFacts.videoFacts(sourceType: facts.sourceType, codec: facts.codec),
            audioFacts: StreamRowFacts.audioFacts(audio: facts.audio, languages: languages,
                                                  locale: Locale.current),
            cachedState: titleCarriesInstant ? nil
                : StreamRowFacts.cachedState(cached: cached, provider: provider)
        )
    }

    /// Row title with the mobile "- <Provider> Instant" suffix on debrid-cached torrent rows
    /// (`StreamCard.kt:instantServiceLabel`), shown only while debrid resolution is enabled and
    /// no custom stream-name template is active (`instantSuffix`).
    @MainActor
    static func title(
        for stream: StreamItem,
        instantSuffix: Bool,
        providerLabel: (StreamDebridCacheStatus) -> String = StreamRowModel.debridProviderLabel
    ) -> String {
        let base = stream.streamLabel
        guard instantSuffix,
              let status = stream.debridCacheStatus,
              status.state == .cached else { return base }
        let provider = providerLabel(status)
        return provider.isEmpty ? base : String(localized: "\(base) - \(provider) Instant")
    }

    /// The provider's short name, else the cache status' own name, else the provider's display name.
    static func debridProviderLabel(_ status: StreamDebridCacheStatus) -> String {
        var provider = DebridProviders.shared.shortName(id: status.providerId)
        if provider.trimmingCharacters(in: .whitespaces).isEmpty {
            provider = status.providerName.trimmingCharacters(in: .whitespaces)
        }
        if provider.isEmpty {
            provider = DebridProviders.shared.displayName(id: status.providerId)
        }
        return provider
    }
}
