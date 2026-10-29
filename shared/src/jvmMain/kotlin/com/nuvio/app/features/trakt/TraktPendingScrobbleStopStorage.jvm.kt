package com.nuvio.app.features.trakt

// JVM actual (test target): same preferences file and key layout as the Android actual, backed by
// JvmSharedPreferences.

import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_KEY
import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES
import com.nuvio.app.core.storage.JvmSharedPreferences
import com.nuvio.app.core.storage.ProfileScopedKey
import com.nuvio.app.core.storage.jvmSharedPreferences

actual object TraktPendingScrobbleStopStorage {
    private val preferences: JvmSharedPreferences? = jvmSharedPreferences(TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES)

    private fun key(profileId: Int): String =
        ProfileScopedKey.of(TRAKT_PENDING_SCROBBLE_STOPS_KEY, profileId)

    actual fun load(profileId: Int): String? =
        preferences?.getString(key(profileId), null)

    actual fun save(profileId: Int, payload: String) {
        preferences?.edit()?.putString(key(profileId), payload)?.apply()
    }

    actual fun clear(profileId: Int) {
        preferences?.edit()?.remove(key(profileId))?.apply()
    }
}
