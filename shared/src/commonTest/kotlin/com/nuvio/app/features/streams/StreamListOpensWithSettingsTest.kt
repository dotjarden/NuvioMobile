package com.nuvio.app.features.streams

import com.nuvio.app.core.account.AccountDataStores
import com.nuvio.app.core.account.AppleKeySpec
import kotlinx.serialization.json.buildJsonObject
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * "Source List Opens With" (Direction C D9): default Best Pick, persists across reloads, unknown
 * stored values fall back, and the key never rides the settings sync (profile-local).
 */
class StreamListOpensWithSettingsTest {
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
    fun defaultsToBestPickWithoutWritingIt() {
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(StreamListOpensWith.BEST_PICK, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        assertNull(StreamBadgeSettingsStorage.loadStreamListOpensWith())
    }

    @Test
    fun fullListSurvivesReload() {
        StreamBadgeSettingsRepository.setListOpensWith(StreamListOpensWith.FULL_LIST)
        StreamBadgeSettingsRepository.clearLocalState()
        StreamBadgeSettingsRepository.ensureLoaded()
        assertEquals(StreamListOpensWith.FULL_LIST, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        assertEquals("full_list", StreamBadgeSettingsStorage.loadStreamListOpensWith())
    }

    @Test
    fun unknownStoredValuesFallBackToBestPick() {
        listOf("tiers", "unknown").forEach { value ->
            StreamBadgeSettingsStorage.saveStreamListOpensWith(value)
            StreamBadgeSettingsRepository.onProfileChanged()
            assertEquals(StreamListOpensWith.BEST_PICK, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        }
    }

    @Test
    fun keyIsAbsentFromTheSyncPayloadExport() {
        StreamBadgeSettingsRepository.setListOpensWith(StreamListOpensWith.FULL_LIST)
        assertNull(StreamBadgeSettingsStorage.exportToSyncPayload()["stream_list_opens_with"])
    }

    @Test
    fun incomingSyncDoesNotResetTheChoice() {
        StreamBadgeSettingsRepository.setListOpensWith(StreamListOpensWith.FULL_LIST)
        StreamBadgeSettingsStorage.replaceFromSyncPayload(buildJsonObject {})
        StreamBadgeSettingsRepository.onProfileChanged()
        assertEquals(StreamListOpensWith.FULL_LIST, StreamBadgeSettingsRepository.uiState.value.listOpensWith)
        assertEquals("full_list", StreamBadgeSettingsStorage.loadStreamListOpensWith())
    }

    @Test
    fun keyIsRegisteredForSignOutWipe() {
        val scoped = AccountDataStores.all.flatMap { it.appleKeys }
            .filterIsInstance<AppleKeySpec.ProfileScoped>().map { it.base }
        assertTrue("stream_list_opens_with" in scoped)
    }
}
