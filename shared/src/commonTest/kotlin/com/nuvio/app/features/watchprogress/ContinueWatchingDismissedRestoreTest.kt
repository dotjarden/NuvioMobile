package com.nuvio.app.features.watchprogress

import com.nuvio.app.features.watched.WatchedItem
import com.nuvio.app.features.watched.dismissedNextUpContentIdsToRestore
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Upstream 6fefbcdab (#2244): marking an episode watched restores a Continue Watching show the
 * user had dismissed. `WatchedRepository.markWatched` itself has no test harness (its load path
 * pulls in the tracking registry and profile store), so the series-id rule is a pure helper,
 * [dismissedNextUpContentIdsToRestore], exercised here against the real preferences repository
 * on the JVM's file-backed storage.
 */
class ContinueWatchingDismissedRestoreTest {
    private fun episode(seriesId: String, season: Int, episode: Int) = WatchedItem(
        id = seriesId,
        type = "series",
        name = seriesId,
        season = season,
        episode = episode,
        markedAtEpochMs = 0L,
    )

    private fun movie(id: String) = WatchedItem(id = id, type = "movie", name = id, markedAtEpochMs = 0L)

    private fun restore(items: Collection<WatchedItem>) {
        dismissedNextUpContentIdsToRestore(items).forEach(
            ContinueWatchingPreferencesRepository::removeDismissedNextUpKeysForContent,
        )
    }

    @BeforeTest
    fun reset() {
        ContinueWatchingPreferencesStorage.savePayload("{}")
        ContinueWatchingPreferencesRepository.clearLocalState()
        ContinueWatchingPreferencesRepository.ensureLoaded()
    }

    @AfterTest
    fun cleanup() = reset()

    @Test
    fun `removeDismissedNextUpKeysForContent drops the bare id and the pipe-suffixed keys`() {
        listOf("tt100", "tt100|1|2", "tt100|3|4", "tt1000", "tt1000|1|1", "tt200|1|1").forEach(
            ContinueWatchingPreferencesRepository::addDismissedNextUpKey,
        )

        ContinueWatchingPreferencesRepository.removeDismissedNextUpKeysForContent(" tt100 ")

        assertEquals(
            setOf("tt1000", "tt1000|1|1", "tt200|1|1"),
            ContinueWatchingPreferencesRepository.uiState.value.dismissedNextUpKeys,
        )
    }

    @Test
    fun `restore ids come from episode items only and are deduplicated`() {
        val ids = dismissedNextUpContentIdsToRestore(
            listOf(
                movie("tt-movie"),
                episode("tt100", 1, 1),
                episode("tt100", 1, 2),
                episode("tt200", 2, 1),
                WatchedItem(id = "tt300", type = "series", name = "series-level", markedAtEpochMs = 0L),
            ),
        )

        assertEquals(listOf("tt100", "tt200"), ids)
    }

    @Test
    fun `marking an episode watched clears that series' dismissed keys and nothing else`() {
        listOf("tt100", "tt100|1|2", "tt200|1|1", "tt-movie").forEach(
            ContinueWatchingPreferencesRepository::addDismissedNextUpKey,
        )

        restore(listOf(episode("tt100", 1, 2)))

        assertEquals(
            setOf("tt200|1|1", "tt-movie"),
            ContinueWatchingPreferencesRepository.uiState.value.dismissedNextUpKeys,
        )
    }

    @Test
    fun `marking a movie watched leaves every dismissed key alone`() {
        listOf("tt-movie", "tt-movie|1|1", "tt100|1|2").forEach(
            ContinueWatchingPreferencesRepository::addDismissedNextUpKey,
        )

        restore(listOf(movie("tt-movie")))

        assertEquals(
            setOf("tt-movie", "tt-movie|1|1", "tt100|1|2"),
            ContinueWatchingPreferencesRepository.uiState.value.dismissedNextUpKeys,
        )
    }
}
