package com.nuvio.app.features.streams

import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Direction C D9: a tvOS profile that never set "Source List Opens With" gets Best Pick, and nothing is written. */
class StreamListOpensWithTvOsDefaultTest {
    @BeforeTest
    fun initialize() = reset()

    @AfterTest
    fun clearState() = reset()

    private fun reset() {
        StreamBadgeSettingsStorage.clearStreamListOpensWith()
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.clearLocalState()
    }

    @Test
    fun freshProfileLoadsBestPickWithoutWritingIt() {
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamListOpensWith.BEST_PICK, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        assertNull(StreamBadgeSettingsStorage.loadStreamListOpensWith())
        assertNull(StreamBadgeSettingsStorage.exportToSyncPayload()["stream_list_opens_with"])
    }

    @Test
    fun fullListIsAnExplicitChoiceThatPersists() {
        StreamBadgeSettingsRepository.setListOpensWith(StreamListOpensWith.FULL_LIST)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()

        assertEquals(StreamListOpensWith.FULL_LIST, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        assertEquals("full_list", StreamBadgeSettingsStorage.loadStreamListOpensWith())
    }
}
