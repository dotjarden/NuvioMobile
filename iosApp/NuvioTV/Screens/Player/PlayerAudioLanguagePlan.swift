import Foundation
import SharedCore

/// Pure decision logic for the mpv audio-language preference (tvOS analogue of upstream
/// 4f79bfe0's proactive `alang`). Kept free of mpv/UIKit so `NuvioTVTests` can cover it.
enum PlayerAudioLanguagePlan {
    /// mpv `alang` option value: the preferred language targets in priority order, comma-joined.
    static func alangValue(targets: [String]) -> String {
        targets.joined(separator: ",")
    }

    /// The track id to force after the track list is known, or `nil` when nothing should change.
    ///
    /// Walks `targets` in priority order. The first target that matches ANY track decides:
    /// if one of its matches is already `selected` (mpv's own `alang` pick satisfied it), return
    /// `nil` so the caller does not re-poke `aid` after the first frame; otherwise return the first
    /// matching track's id. No target matches at all → `nil` (leave mpv's default alone).
    /// Language matching delegates to the shared Kotlin matcher so `jpn`/`ja`, `pt-BR`/`pt` etc.
    /// behave exactly as the rest of the app.
    static func trackToForce(
        targets: [String],
        tracks: [(id: Int, lang: String, selected: Bool)]
    ) -> Int? {
        for target in targets {
            let matches = tracks.filter {
                PlayerLanguagePreferencesKt.languageMatchesPreference(trackLanguage: $0.lang, targetLanguage: target)
            }
            guard !matches.isEmpty else { continue }
            if matches.contains(where: { $0.selected }) { return nil }
            return matches.first?.id
        }
        return nil
    }

    /// The title's original language for the "Original" audio preference, or nil when unknown.
    /// Prefers the value carried on the launch context (filled by `PlaybackMeta.init(details:)` on
    /// the Detail / episode-shelf paths); falls back to the shared meta-details cache, which is warm
    /// whenever the title's Detail page was opened this session and cold on Home continue-watching
    /// or deep-link launches (then nil — same as today's behavior, never worse). Shared by both
    /// engines (mpv `MPVPlayerView`, native `NativePlaybackCoordinator`) so they cannot diverge.
    static func originalLanguage(for context: PlaybackContext) -> String? {
        if let fromContext = context.meta?.originalLanguage, !fromContext.isEmpty {
            return fromContext
        }
        guard let details = MetaDetailsRepository.shared.peek(type: context.contentType, id: context.parentMetaId)
        else { return nil }
        return PlayerLanguagePreferencesKt.resolveContentLanguage(language: details.language, country: details.country)
    }
}
