package com.nuvio.app.features.streams

import com.nuvio.app.core.sync.decodeSyncString
import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Port of upstream `50d39823`'s `StreamBackgroundSettingsTest` (Robolectric + Compose
 * `androidHostTest`) to a platform-neutral `commonTest`. Kept: default, reload + sync round trip,
 * older-settings restore, removed/unknown modes. Dropped: the Compose picker, tablet-hiding and
 * settings-search cases (composeApp UI, no shared/ seam) and the other-profile SharedPreferences
 * assertion (needs the Android handle). The store is reset through `replaceFromSyncPayload`, which
 * clears every synced key for the current profile.
 *
 * Stream picker A, P0.3 (decision D1): the default is [StreamBackgroundDefaults.platformDefault]
 * (Normal on the JVM and iOS, Cinematic on tvOS), so these cases hold on both test targets; the
 * per-platform value itself is pinned by `StreamBackgroundJvmDefaultTest` and
 * `StreamBackgroundTvOsDefaultTest`.
 */
class StreamBackgroundSettingsTest {
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
    fun existingProfilesUseThePlatformDefaultBackground() {
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(StreamBackgroundDefaults.platformDefault, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
    }

    @Test
    fun explicitBackgroundSurvivesReloadAndSettingsSync() {
        // The mode that is NOT the platform default (Cinematic on the JVM, Normal on tvOS), so the
        // call below is a real change that gets written; setting the default is a no-op write.
        val explicit = StreamBackgroundMode.entries.first { it != StreamBackgroundDefaults.platformDefault }
        StreamBadgeSettingsRepository.setBackgroundMode(explicit)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(explicit, StreamBadgeSettingsRepository.uiState.value.backgroundMode)

        val payload = StreamBadgeSettingsStorage.exportToSyncPayload()
        assertEquals(explicit.name.lowercase(), payload.decodeSyncString("stream_background_mode"))
        StreamBadgeSettingsRepository.setBackgroundMode(StreamBackgroundDefaults.platformDefault)
        StreamBadgeSettingsStorage.replaceFromSyncPayload(payload)
        StreamBadgeSettingsRepository.onProfileChanged()
        assertEquals(explicit, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
    }

    @Test
    fun olderSettingsRestoreTheDefault() {
        StreamBadgeSettingsRepository.setBackgroundMode(StreamBackgroundMode.Cinematic)

        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.onProfileChanged()

        assertEquals(StreamBackgroundDefaults.platformDefault, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
        assertNull(StreamBadgeSettingsStorage.loadStreamBackgroundMode())
    }

    @Test
    fun removedAndUnknownBackgroundModesFallBackToThePlatformDefault() {
        listOf("dominantcolor", "unknown").forEach { mode ->
            StreamBadgeSettingsStorage.saveStreamBackgroundMode(mode)
            StreamBadgeSettingsRepository.onProfileChanged()
            assertEquals(StreamBackgroundDefaults.platformDefault, StreamBadgeSettingsRepository.uiState.value.backgroundMode)
        }
    }
}
