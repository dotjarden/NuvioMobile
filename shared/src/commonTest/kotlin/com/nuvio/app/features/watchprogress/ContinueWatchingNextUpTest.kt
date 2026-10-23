package com.nuvio.app.features.watchprogress

import com.nuvio.app.features.watched.WatchedItem
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** tvOS Up Next (fork): seed selection and the row merge in `ContinueWatchingNextUp.kt`. */
class ContinueWatchingNextUpTest {
    private val t0 = 1_700_000_000_000L

    private fun progress(
        seriesId: String,
        season: Int,
        episode: Int,
        at: Long,
        completed: Boolean,
        type: String = "series",
    ) = WatchProgressEntry(
        contentType = type,
        parentMetaId = seriesId,
        parentMetaType = type,
        videoId = "$seriesId:$season:$episode",
        title = seriesId,
        seasonNumber = season,
        episodeNumber = episode,
        lastPositionMs = if (completed) 3_000_000L else 600_000L,
        durationMs = 3_000_000L,
        lastUpdatedEpochMs = at,
        isCompleted = completed,
    )

    private fun watched(seriesId: String, season: Int, episode: Int, at: Long) = WatchedItem(
        id = seriesId,
        type = "series",
        name = seriesId,
        season = season,
        episode = episode,
        markedAtEpochMs = at,
    )

    private fun seeds(
        entries: List<WatchProgressEntry>,
        watched: List<WatchedItem> = emptyList(),
        dismissed: Set<String> = emptySet(),
        cutoff: Long? = null,
        dropped: Set<String> = emptySet(),
    ) = buildContinueWatchingNextUpSeeds(
        progressEntries = entries,
        watchedItems = watched,
        isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
        isDroppedShow = { it in dropped },
        recencyCutoffEpochMs = cutoff,
        preferFurthestEpisode = true,
        dismissedNextUpKeys = dismissed,
    )

    @Test
    fun finishedEpisodeSeedsItsSeries() {
        val result = seeds(listOf(progress("tt1", 1, 3, t0, completed = true)))
        assertEquals(listOf(ContinueWatchingNextUpSeed("series", "tt1", 1, 3, t0)), result)
    }

    @Test
    fun moviesAndSpecialsNeverSeed() {
        val result = seeds(
            listOf(
                progress("tt-movie", 1, 1, t0, completed = true, type = "movie"),
                progress("tt2", 0, 1, t0, completed = true),
            ),
        )
        assertTrue(result.isEmpty())
    }

    @Test
    fun newerInProgressEpisodeSuppressesTheSeries() {
        val result = seeds(
            listOf(
                progress("tt1", 1, 3, t0, completed = true),
                progress("tt1", 1, 4, t0 + 1_000, completed = false),
            ),
        )
        assertTrue(result.isEmpty())
    }

    @Test
    fun olderInProgressEpisodeDoesNotSuppress() {
        val result = seeds(
            listOf(
                progress("tt1", 1, 2, t0, completed = false),
                progress("tt1", 1, 3, t0 + 1_000, completed = true),
            ),
        )
        assertEquals(1, result.size)
    }

    @Test
    fun watchedHistorySeedsAndFurthestEpisodeWins() {
        val result = seeds(
            entries = listOf(progress("tt1", 1, 2, t0 + 5_000, completed = true)),
            watched = listOf(watched("tt1", 2, 1, t0)),
        )
        assertEquals(2, result.single().seasonNumber)
        assertEquals(1, result.single().episodeNumber)
    }

    @Test
    fun dismissedDroppedAndOutOfWindowSeriesAreSkipped() {
        val entries = listOf(
            progress("dismissed", 1, 1, t0, completed = true),
            progress("dropped", 1, 1, t0, completed = true),
            progress("old", 1, 1, t0 - 10_000, completed = true),
            progress("kept", 1, 1, t0, completed = true),
        )
        val result = seeds(
            entries = entries,
            dismissed = setOf(nextUpDismissKey("dismissed", 1, 1)),
            dropped = setOf("dropped"),
            cutoff = t0 - 1,
        )
        assertEquals(listOf("kept"), result.map { it.contentId })
    }

    @Test
    fun mergeKeepsInProgressCardAndSortsByRecency() {
        val inProgress = listOf(progress("a", 1, 2, t0, completed = false))
        val nextUp = listOf(
            progress("a", 1, 3, t0 + 5_000, completed = false).copy(source = WatchProgressSourceNextUp),
            progress("b", 2, 1, t0 + 9_000, completed = false).copy(source = WatchProgressSourceNextUp),
        )
        val merged = mergeContinueWatchingWithNextUp(inProgress, nextUp)
        assertEquals(listOf("b:2:1", "a:1:2"), merged.map { it.videoId })
        assertTrue(merged.first().isContinueWatchingNextUp)
    }
}
