package com.nuvio.app.features.trakt

/**
 * Persists one profile's pending Trakt scrobble stops (a JSON list, see
 * [TraktPendingScrobbleStopQueue]) under `core.account.TRAKT_PENDING_SCROBBLE_STOPS_KEY`.
 * Addressed by an explicit profile id, never the active one, so a stop is always kept under the
 * profile that played it. Registered in `AccountDataStores`, so sign-out wipes it.
 */
expect object TraktPendingScrobbleStopStorage {
    fun load(profileId: Int): String?
    fun save(profileId: Int, payload: String)
    fun clear(profileId: Int)
}
