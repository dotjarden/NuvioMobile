package com.nuvio.app.features.streams

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Stream picker A, P0.1: the per-add-on chip survives a refresh of the same title and resets on a
 * new one (decision in `docs/stream-picker-addons-plan-2026-10-25.md` §2 P0.1). The token rule is
 * the one `StreamsRepository.load` applies before any group exists; `clear()` is covered through
 * the repository itself because it is the one path tvOS's picker calls today.
 */
class StreamFilterRetentionTest {

    private val previousFlag = StreamPresentationPlatform.selectedFilterSurvivesRefresh

    @BeforeTest
    fun enableTvOsRule() {
        StreamPresentationPlatform.selectedFilterSurvivesRefresh = true
    }

    @AfterTest
    fun restore() {
        StreamPresentationPlatform.selectedFilterSurvivesRefresh = previousFlag
        StreamsRepository.clear()
    }

    @Test
    fun sameTitleRefreshKeepsTheChip() {
        val previous = StreamsUiState(requestToken = DUNE, selectedFilter = "addon:comet")

        assertEquals("addon:comet", StreamFilterRetention.carriedFilter(previous, DUNE))
    }

    @Test
    fun newTitleResetsToAll() {
        val previous = StreamsUiState(requestToken = DUNE, selectedFilter = "addon:comet")

        assertNull(StreamFilterRetention.carriedFilter(previous, ANIMALS))
    }

    @Test
    fun newEpisodeOfTheSameSeriesResetsToAll() {
        val episode3 = StreamsRepository.requestToken("series", "tt1:1:3", manualSelection = true)
        val episode4 = StreamsRepository.requestToken("series", "tt1:1:4", manualSelection = true)
        val previous = StreamsUiState(requestToken = episode3, selectedFilter = "addon:comet")

        assertNull(StreamFilterRetention.carriedFilter(previous, episode4))
    }

    @Test
    fun noPreviousTokenMeansNoCarry() {
        // What `clear()` leaves behind: no token, so nothing to match.
        val cleared = StreamsUiState(selectedFilter = "addon:comet")

        assertNull(StreamFilterRetention.carriedFilter(cleared, DUNE))
    }

    @Test
    fun mobileKeepsUpstreamBehaviour() {
        StreamPresentationPlatform.selectedFilterSurvivesRefresh = false
        val previous = StreamsUiState(requestToken = DUNE, selectedFilter = "addon:comet")

        assertNull(StreamFilterRetention.carriedFilter(previous, DUNE))
    }

    @Test
    fun carriedChipMustStillBeInTheFanOut() {
        val groups = listOf(
            AddonStreamGroup(addonName = "Comet", addonId = "addon:comet", streams = emptyList(), isLoading = true),
            AddonStreamGroup(addonName = "Torrentio", addonId = "addon:torrentio", streams = emptyList(), isLoading = true),
        )

        assertEquals("addon:comet", StreamFilterRetention.validated("addon:comet", groups))
        assertNull(StreamFilterRetention.validated("addon:removed", groups))
        assertNull(StreamFilterRetention.validated(null, groups))
    }

    @Test
    fun selectFilterRoundTripsAndClearResets() {
        StreamsRepository.selectFilter("addon:comet")
        assertEquals("addon:comet", StreamsRepository.uiState.value.selectedFilter)

        StreamsRepository.selectFilter(null)
        assertNull(StreamsRepository.uiState.value.selectedFilter)

        StreamsRepository.selectFilter("addon:torrentio")
        StreamsRepository.clear()
        assertNull(StreamsRepository.uiState.value.selectedFilter)
        assertNull(StreamsRepository.uiState.value.requestToken)
    }

    @Test
    fun filteredGroupsFollowTheChip() {
        val comet = AddonStreamGroup(addonName = "Comet", addonId = "addon:comet", streams = emptyList())
        val torrentio = AddonStreamGroup(addonName = "Torrentio", addonId = "addon:torrentio", streams = emptyList())
        val all = StreamsUiState(groups = listOf(comet, torrentio))

        assertEquals(listOf(comet, torrentio), all.filteredGroups)
        assertEquals(listOf(torrentio), all.copy(selectedFilter = "addon:torrentio").filteredGroups)
        assertEquals(emptyList(), all.copy(selectedFilter = "addon:gone").filteredGroups)
    }

    private companion object {
        val DUNE = StreamsRepository.requestToken("movie", "tt1160419", manualSelection = true)
        val ANIMALS = StreamsRepository.requestToken("movie", "tt30000000", manualSelection = true)
    }
}
