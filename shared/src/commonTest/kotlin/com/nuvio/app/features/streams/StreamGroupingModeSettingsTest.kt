package com.nuvio.app.features.streams

import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * "Group Sources By" (polish D5, Q1 = profile-local): default Quality, persists across reloads,
 * unknown stored values fall back, and the key never rides the settings sync (like
 * `show_addon_logo`), so an incoming sync blob cannot reset it.
 */
class StreamGroupingModeSettingsTest {
    @BeforeTest
    fun initialize() = reset()

    @AfterTest
    fun clearState() = reset()

    private fun reset() {
        StreamBadgeSettingsStorage.clearStreamGroupingMode()
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.clearLocalState()
    }

    @Test
    fun defaultsToQualityWithoutWritingIt() {
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(StreamGroupingMode.QUALITY, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        assertNull(StreamBadgeSettingsStorage.loadStreamGroupingMode())
    }

    @Test
    fun addonChoiceSurvivesReload() {
        StreamBadgeSettingsRepository.setGroupingMode(StreamGroupingMode.ADDON)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(StreamGroupingMode.ADDON, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        assertEquals("addon", StreamBadgeSettingsStorage.loadStreamGroupingMode())
    }

    @Test
    fun unknownStoredValuesFallBackToQuality() {
        listOf("tiers", "unknown").forEach { value ->
            StreamBadgeSettingsStorage.saveStreamGroupingMode(value)
            StreamBadgeSettingsRepository.onProfileChanged()
            assertEquals(StreamGroupingMode.QUALITY, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        }
    }

    @Test
    fun keyIsAbsentFromTheSyncPayloadExport() {
        StreamBadgeSettingsRepository.setGroupingMode(StreamGroupingMode.ADDON)
        assertNull(StreamBadgeSettingsStorage.exportToSyncPayload()["stream_grouping_mode"])
    }

    @Test
    fun incomingSyncDoesNotResetTheChoice() {
        StreamBadgeSettingsRepository.setGroupingMode(StreamGroupingMode.ADDON)
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.onProfileChanged()
        assertEquals(StreamGroupingMode.ADDON, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        assertEquals("addon", StreamBadgeSettingsStorage.loadStreamGroupingMode())
    }
}
