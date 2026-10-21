import SharedCore

/// FEAT-84 (GitHub #10 item 4), "Off stays Off": the subtitle fallback language must never turn
/// subtitles on when the primary Subtitles setting is Off.
///
/// The shared `resolvePreferredSubtitleLanguageTargets` returns the secondary (fallback) language
/// even when the primary is `none`, so a fallback set on mobile, or on tvOS before Subtitles was
/// switched Off, would auto-select a subtitle track. Both players pass their subtitle secondary
/// through `effectiveSecondary` at the auto-selection site (mpv `autoSelectPreferredTracks`,
/// native `resolveLanguagePlan`): with the primary Off it is nil, the target list is empty, and
/// both engines treat an empty plan as subtitles off (mpv: `MPVSubtitleAutoSelectGate`'s
/// `noTargets`; native: `subtitlesOff`). The rule mirrors the shared one: the primary is
/// normalized, and a blank primary counts as `none`.
///
/// Not covered, by design: the raw secondary still reaches the list filter and ordering helpers
/// (`filterAddonSubtitlesForSettings` / `preferredSubtitleTargetsForSettings` in the mpv add-on
/// path and the native add-on watcher, and the stream picker). Those only filter or order
/// lists and never enable a track. One visible effect: with Off, a fallback and "Show only
/// preferred languages", the native panel lists every embedded language (its filter list is the
/// empty target list) while the add-on list keeps only the fallback language.
///
/// The shared NONE + secondary behaviour is an upstream-report candidate; mobile is unchanged
/// and there is no shared Kotlin change here.
nonisolated enum SubtitleFallbackGuard {
    /// The subtitle secondary to hand the shared target resolver: nil when `primary` is Off.
    static func effectiveSecondary(primary: String, secondary: String?) -> String? {
        let normalized = PlayerLanguagePreferencesKt.normalizeLanguageCode(language: primary)
            ?? SubtitleLanguageOption.shared.NONE
        return normalized == SubtitleLanguageOption.shared.NONE ? nil : secondary
    }
}
