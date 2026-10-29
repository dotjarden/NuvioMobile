package com.nuvio.app.features.streams

import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Polish D5: a tvOS profile that never set "Group Sources By" gets Quality, and nothing is written. */
class StreamGroupingTvOsDefaultTest {
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
    fun freshProfileLoadsQualityWithoutWritingIt() {
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamGroupingMode.QUALITY, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        assertNull(StreamBadgeSettingsStorage.loadStreamGroupingMode())
        assertNull(StreamBadgeSettingsStorage.exportToSyncPayload()["stream_grouping_mode"])
    }

    @Test
    fun addonIsAnExplicitChoiceThatPersists() {
        StreamBadgeSettingsRepository.setGroupingMode(StreamGroupingMode.ADDON)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamGroupingMode.ADDON, StreamBadgeSettingsRepository.uiState.value.groupingMode)
        assertEquals("addon", StreamBadgeSettingsStorage.loadStreamGroupingMode())
    }
}
