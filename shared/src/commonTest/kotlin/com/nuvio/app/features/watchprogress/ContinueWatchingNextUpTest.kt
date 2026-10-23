package com.nuvio.app.features.watchprogress

import com.nuvio.app.features.details.MetaVideo
import com.nuvio.app.features.watched.WatchedItem
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** FEAT-85 Up Next (based on erdist's patch, GitHub #11): seed selection, merge and dismissal in `ContinueWatchingNextUp.kt`. */
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
    fun inProgressTieWithTheCompletionSuppressesTheSeries() {
        val result = seeds(
            listOf(
                progress("tt1", 1, 3, t0, completed = true),
                progress("tt1", 1, 4, t0, completed = false),
            ),
        )
        assertTrue(result.isEmpty())
    }

    @Test
    fun latestMarkedEpisodeWinsWhenFurthestIsOff() {
        val result = buildContinueWatchingNextUpSeeds(
            progressEntries = listOf(progress("tt1", 1, 2, t0 + 5_000, completed = true)),
            watchedItems = listOf(watched("tt1", 2, 1, t0)),
            isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
            isDroppedShow = { false },
            recencyCutoffEpochMs = null,
            preferFurthestEpisode = false,
            dismissedNextUpKeys = emptySet(),
        )
        assertEquals(ContinueWatchingNextUpSeed("series", "tt1", 1, 2, t0 + 5_000), result.single())
    }

    @Test
    fun aDismissalOnlyHidesTheSeedEpisodeItWasMadeFor() {
        // The phone keys a dismissal by the finished episode; finishing the next one brings the
        // series back (a new seed, a new key).
        val result = seeds(
            entries = listOf(
                progress("tt1", 1, 3, t0, completed = true),
                progress("tt1", 1, 4, t0 + 1_000, completed = true),
            ),
            dismissed = setOf(nextUpDismissKey("tt1", 1, 3)),
        )
        assertEquals(4, result.single().episodeNumber)
    }

    @Test
    fun seedsAreMostRecentFirstAndCapped() {
        val entries = (1..5).map { index -> progress("tt$index", 1, 1, t0 + index, completed = true) }
        val result = buildContinueWatchingNextUpSeeds(
            progressEntries = entries,
            watchedItems = emptyList(),
            isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
            isDroppedShow = { false },
            recencyCutoffEpochMs = null,
            preferFurthestEpisode = true,
            dismissedNextUpKeys = emptySet(),
            limit = 3,
        )
        assertEquals(listOf("tt5", "tt4", "tt3"), result.map { it.contentId })
    }

    @Test
    fun theProviderSeedRuleIsHonoured() {
        val result = buildContinueWatchingNextUpSeeds(
            progressEntries = listOf(progress("tt1", 1, 3, t0, completed = true)),
            watchedItems = emptyList(),
            isProgressSeed = { false },
            isDroppedShow = { false },
            recencyCutoffEpochMs = null,
            preferFurthestEpisode = true,
            dismissedNextUpKeys = emptySet(),
        )
        assertTrue(result.isEmpty())
    }

    @Test
    fun mergeKeepsTheMoreRecentCardPerSeries() {
        // "a": an episode abandoned before a later one was finished, so its next-up is newer and
        // wins (mobile's rule). "c": the next-up is older than the in-progress card, which stays.
        val inProgress = listOf(
            progress("c", 1, 5, t0 + 7_000, completed = false),
            progress("a", 1, 2, t0, completed = false),
        )
        val nextUp = listOf(
            progress("a", 1, 4, t0 + 5_000, completed = false).copy(source = WatchProgressSourceNextUp),
            progress("b", 2, 1, t0 + 9_000, completed = false).copy(source = WatchProgressSourceNextUp),
            progress("c", 1, 4, t0 + 1_000, completed = false).copy(source = WatchProgressSourceNextUp),
        )
        val merged = mergeContinueWatchingWithNextUp(inProgress, nextUp)
        assertEquals(listOf("b:2:1", "c:1:5", "a:1:4"), merged.map { it.videoId })
        assertTrue(merged.first().isContinueWatchingNextUp)
        assertFalse(merged[1].isContinueWatchingNextUp)
    }

    @Test
    fun mergeTieKeepsTheInProgressCard() {
        val inProgress = listOf(progress("a", 1, 2, t0, completed = false))
        val nextUp = listOf(progress("a", 1, 3, t0, completed = false).copy(source = WatchProgressSourceNextUp))
        assertEquals(listOf("a:1:2"), mergeContinueWatchingWithNextUp(inProgress, nextUp).map { it.videoId })
    }

    @Test
    fun mergeWithNothingToAddReturnsTheSameList() {
        val inProgress = listOf(progress("a", 1, 2, t0, completed = false))
        assertSame(inProgress, mergeContinueWatchingWithNextUp(inProgress, emptyList()))
    }

    @Test
    fun withoutDismissedDropsOnlyDismissedNextUpCards() {
        val nextUpA = progress("a", 1, 4, t0, completed = false).copy(source = WatchProgressSourceNextUp)
        val nextUpB = progress("b", 2, 1, t0, completed = false).copy(source = WatchProgressSourceNextUp)
        val inProgressC = progress("c", 1, 1, t0, completed = false)
        val keys = mapOf(
            nextUpA.videoId to nextUpDismissKey("a", 1, 3),
            nextUpB.videoId to nextUpDismissKey("b", 1, 10),
            // A progress card that happens to share a key is never dropped by this filter.
            inProgressC.videoId to nextUpDismissKey("c", 1, 1),
        )
        val result = withoutDismissedNextUp(
            entries = listOf(nextUpA, nextUpB, inProgressC),
            dismissKeyByVideoId = keys,
            dismissedNextUpKeys = setOf(nextUpDismissKey("a", 1, 3), nextUpDismissKey("c", 1, 1)),
        )
        assertEquals(listOf(nextUpB.videoId, inProgressC.videoId), result.map { it.videoId })
    }

    @Test
    fun resolveKeyChangesWithEveryInputThatChangesTheAnswer() {
        val seed = ContinueWatchingNextUpSeed("series", "tt1", 1, 3, t0)
        val base = nextUpResolveKey(seed, 1, "NUVIO_SYNC", preferFurthestEpisode = true, showUnairedNextUp = true, todayIsoDate = "2026-10-23")
        val variants = listOf(
            nextUpResolveKey(seed.copy(episodeNumber = 4), 1, "NUVIO_SYNC", true, true, "2026-10-23"),
            nextUpResolveKey(seed.copy(contentId = "tt2"), 1, "NUVIO_SYNC", true, true, "2026-10-23"),
            nextUpResolveKey(seed, 1, "TRAKT", true, true, "2026-10-23"),
            nextUpResolveKey(seed, 1, "NUVIO_SYNC", false, true, "2026-10-23"),
            nextUpResolveKey(seed, 1, "NUVIO_SYNC", true, false, "2026-10-23"),
            nextUpResolveKey(seed, 1, "NUVIO_SYNC", true, true, "2026-10-24"),
            nextUpResolveKey(seed, 2, "NUVIO_SYNC", true, true, "2026-10-23"),
        )
        variants.forEach { assertNotEquals(base, it) }
        // Re-finishing the same episode later re-dates the card but does not refetch it.
        assertEquals(base, nextUpResolveKey(seed.copy(markedAtEpochMs = t0 + 1), 1, "NUVIO_SYNC", true, true, "2026-10-23"))
    }

    @Test
    fun unairedEpisodesAreDroppedUnderTheCurrentPolicy() {
        assertEquals(UnairedNextUpPolicy.Drop, ContinueWatchingUnairedNextUpPolicy)
        assertTrue(keepNextUpEpisode(isReleased = true, policy = UnairedNextUpPolicy.Drop))
        assertFalse(keepNextUpEpisode(isReleased = false, policy = UnairedNextUpPolicy.Drop))
        // The flip Christian may choose later keeps the card (to be labelled "Airs <date>").
        assertTrue(keepNextUpEpisode(isReleased = false, policy = UnairedNextUpPolicy.LabelAirDate))
    }

    @Test
    fun nextUpVideoMatchesBySeasonEpisodeThenPlaybackId() {
        val videos = listOf(
            MetaVideo(id = "tt1:1:4", title = "Four", released = "2026-01-01", season = 1, episode = 4),
            MetaVideo(id = "addon-ep-5", title = "Five", released = "2099-01-01", season = 1, episode = 5),
        )
        assertEquals("Four", nextUpVideoFor(videos, "tt1", 1, 4, "ignored")?.title)
        assertEquals("Five", nextUpVideoFor(videos, "tt1", null, null, "addon-ep-5")?.title)
        assertEquals("Four", nextUpVideoFor(videos, "tt1", null, null, "tt1:1:4")?.title)
        assertNull(nextUpVideoFor(videos, "tt1", 2, 1, "tt1:2:1"))
    }

    @Test
    fun removingAnInProgressCardNamesTheUpNextItWouldUncover() {
        // E3 finished, E4 half watched after it: Remove on E4 must dismiss the E3 seed (Up Next E4).
        val entries = listOf(
            progress("tt1", 1, 3, t0, completed = true),
            progress("tt1", 1, 4, t0 + 1_000, completed = false),
            progress("other", 1, 9, t0 + 2_000, completed = true),
        )
        val seed = nextUpSeedAfterRemoval(
            progressEntries = entries,
            watchedItems = emptyList(),
            contentId = "tt1",
            removedVideoId = "tt1:1:4",
            isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
            preferFurthestEpisode = true,
        )
        assertEquals(ContinueWatchingNextUpSeed("series", "tt1", 1, 3, t0), seed)
    }

    @Test
    fun removingWithNothingFinishedDismissesNothing() {
        val seed = nextUpSeedAfterRemoval(
            progressEntries = listOf(progress("tt1", 1, 1, t0, completed = false)),
            watchedItems = emptyList(),
            contentId = "tt1",
            removedVideoId = "tt1:1:1",
            isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
            preferFurthestEpisode = true,
        )
        assertNull(seed)
    }

    @Test
    fun removingUsesWatchedHistoryToo() {
        val seed = nextUpSeedAfterRemoval(
            progressEntries = listOf(progress("tt1", 1, 4, t0 + 1_000, completed = false)),
            watchedItems = listOf(watched("tt1", 1, 3, t0), watched("tt9", 2, 2, t0)),
            contentId = "tt1",
            removedVideoId = "tt1:1:4",
            isProgressSeed = { it.shouldUseAsCompletedSeedForContinueWatching() },
            preferFurthestEpisode = true,
        )
        assertEquals(3, seed?.episodeNumber)
        assertEquals("tt1", seed?.contentId)
    }

    @Test
    fun recentMarksAreScopedToTheProfileAndTheWindow() {
        val marks = listOf(
            RecentNextUpMark(1, watched("tt1", 1, 4, t0)),
            RecentNextUpMark(2, watched("tt2", 1, 1, t0)),
            RecentNextUpMark(1, watched("tt3", 1, 1, t0 - ContinueWatchingNextUpTraktMarkWindowMs - 1)),
        )
        val active = activeRecentNextUpMarks(marks, profileId = 1, nowEpochMs = t0 + 1_000)
        assertEquals(listOf("tt1"), active.map { it.id })
    }

    @Test
    fun aRecentMarkSeedsTheNextEpisodeWhenHistoryIsOff() {
        // Under Trakt the only "history" is the recent mark: E4 marked from its Up Next card makes
        // E4 the seed although Trakt's progress still says E3.
        val result = seeds(
            entries = listOf(progress("tt1", 1, 3, t0, completed = true)),
            watched = activeRecentNextUpMarks(listOf(RecentNextUpMark(1, watched("tt1", 1, 4, t0 + 5_000))), 1, t0 + 6_000),
        )
        assertEquals(4, result.single().episodeNumber)
    }
}
