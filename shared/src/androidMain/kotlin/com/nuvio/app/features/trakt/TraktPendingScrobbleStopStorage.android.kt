package com.nuvio.app.features.trakt

import android.content.Context
import android.content.SharedPreferences
import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_KEY
import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES
import com.nuvio.app.core.storage.ProfileScopedKey

actual object TraktPendingScrobbleStopStorage {
    private var preferences: SharedPreferences? = null

    fun initialize(context: Context) {
        preferences = context.getSharedPreferences(TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES, Context.MODE_PRIVATE)
    }

    private fun key(profileId: Int): String =
        ProfileScopedKey.of(TRAKT_PENDING_SCROBBLE_STOPS_KEY, profileId)

    actual fun load(profileId: Int): String? =
        preferences?.getString(key(profileId), null)

    actual fun save(profileId: Int, payload: String) {
        // commit(), not apply(): a write-ahead entry must be on disk before the request leaves.
        preferences?.edit()?.putString(key(profileId), payload)?.commit()
    }

    actual fun clear(profileId: Int) {
        preferences?.edit()?.remove(key(profileId))?.commit()
    }
}
