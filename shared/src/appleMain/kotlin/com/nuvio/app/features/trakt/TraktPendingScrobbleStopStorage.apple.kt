package com.nuvio.app.features.trakt

import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_KEY
import com.nuvio.app.core.storage.ProfileScopedKey
import platform.Foundation.NSUserDefaults

actual object TraktPendingScrobbleStopStorage {
    private fun key(profileId: Int): String =
        ProfileScopedKey.of(TRAKT_PENDING_SCROBBLE_STOPS_KEY, profileId)

    actual fun load(profileId: Int): String? =
        NSUserDefaults.standardUserDefaults.stringForKey(key(profileId))

    actual fun save(profileId: Int, payload: String) {
        NSUserDefaults.standardUserDefaults.setObject(payload, forKey = key(profileId))
    }

    actual fun clear(profileId: Int) {
        NSUserDefaults.standardUserDefaults.removeObjectForKey(key(profileId))
    }
}
