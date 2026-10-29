package com.nuvio.app.features.player

import com.nuvio.app.core.storage.ProfileScopedKey
import com.nuvio.app.core.storage.jvmSharedPreferences
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** P5 B23: the jvm actual's per-show playback speed storage (the decode guard, end to end). */
class PlayerTrackPreferenceStorageJvmTest {
    private val showId = "tt-p5-speed-test"

    @AfterTest
    fun cleanUp() {
        PlayerTrackPreferenceStorage.clearPlaybackSpeed(showId)
    }

    @Test
    fun playbackSpeedRoundTrips() {
        assertNull(PlayerTrackPreferenceStorage.loadPlaybackSpeed(showId))
        PlayerTrackPreferenceStorage.savePlaybackSpeed(showId, 1.25)
        assertEquals(1.25, PlayerTrackPreferenceStorage.loadPlaybackSpeed(showId))
        PlayerTrackPreferenceStorage.clearPlaybackSpeed(showId)
        assertNull(PlayerTrackPreferenceStorage.loadPlaybackSpeed(showId))
    }

    @Test
    fun storedOutOfRangeSpeedReadsBackNull() {
        jvmSharedPreferences("nuvio_player_track_preferences")
            .edit()
            .putInt(ProfileScopedKey.of("playback_speed|$showId"), 300)
            .apply()
        assertNull(PlayerTrackPreferenceStorage.loadPlaybackSpeed(showId))
    }
}
