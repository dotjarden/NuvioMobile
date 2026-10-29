package com.nuvio.app.features.streams

import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Decision D1 (2026-10-25): on tvOS a profile that never set "Source Background" gets the
 * cinematic picker, and that default is not written to the sync payload on its own.
 */
class StreamBackgroundTvOsDefaultTest {
    @BeforeTest
    fun initialize() {
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.clearLocalState()
    }

    @AfterTest
    fun clearState() {
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.clearLocalState()
    }

    @Test
    fun tvOsDefaultsToCinematic() {
        assertEquals(StreamBackgroundMode.Cinematic, StreamBackgroundDefaults.platformDefault)
    }

    @Test
    fun freshProfileLoadsCinematicWithoutWritingIt() {
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamBackgroundMode.Cinematic, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
        assertNull(StreamBadgeSettingsStorage.loadStreamBackgroundMode())
        assertNull(StreamBadgeSettingsStorage.exportToSyncPayload()["stream_background_mode"])
    }

    @Test
    fun normalIsStillAnExplicitChoice() {
        StreamBadgeSettingsRepository.setBackgroundMode(StreamBackgroundMode.Normal)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamBackgroundMode.Normal, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
        assertEquals("normal", StreamBadgeSettingsStorage.loadStreamBackgroundMode())
    }
}
