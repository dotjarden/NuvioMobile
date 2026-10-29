package com.nuvio.app.features.streams

/**
 * Stream picker A, P0.3 (decision D1, 2026-10-25): the backdrop mode a profile gets before it has
 * ever set "Source Background". tvOS ships the cinematic picker on by default; every other target
 * keeps upstream's Normal (plain background) so mobile behaviour does not change.
 *
 * Read by [StreamBadgeSettingsRepository] wherever it used to hard-code `Normal`: the initial
 * state, `clearLocalState`, and the fallback when the stored value is missing or unknown. The
 * value is never written to the sync payload on its own, so a tvOS profile that stays on the
 * default does not push "cinematic" into the phone's settings.
 */
expect object StreamBackgroundDefaults {
    val platformDefault: StreamBackgroundMode
}
