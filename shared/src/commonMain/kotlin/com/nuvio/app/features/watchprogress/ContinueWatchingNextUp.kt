package com.nuvio.app.features.watchprogress

import com.nuvio.app.features.details.MetaDetailsRepository
import com.nuvio.app.features.details.seriesPrimaryAction
import com.nuvio.app.features.trakt.TraktSettingsRepository
import com.nuvio.app.features.watched.WatchedItem
import com.nuvio.app.features.watched.WatchedRepository
import com.nuvio.app.features.watched.normalizeWatchedMarkedAtEpochMs
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * tvOS "Up Next" for the Home Continue Watching row (fork addition).
 *
 * The shared row ([buildContinueWatchingRowEntries]) only lists titles that are started and not
 * finished, so a series drops out of the row as soon as an episode ends. Mobile fixes that inside
 * composeApp's `HomeScreen.kt` (next-up items built per series); tvOS can't use that code. This is
 * a smaller version of the same idea that lives in :shared:
 *
 * 1. Seeds: per series, the latest completed episode, from watch progress (provider-aware via
 *    [WatchProgressRepository.shouldUseAsNextUpSeed]) plus watched history (not under Trakt, where
 *    the provider's own history already covers it, as on mobile).
 * 2. A series is skipped when it already has an in-progress episode at least as recent as that
 *    completion (the in-progress card is the right one to show), when the active provider hides it,
 *    when it is outside the provider's recency window, or when its next-up was dismissed (the same
 *    profile-synced `dismissedNextUpKeys` mobile uses).
 * 3. The next episode comes from the same shared `seriesPrimaryAction` Detail's Play button uses,
 *    honouring "Up next from furthest episode" and "Show unaired next up".
 *
 * Each result is a synthetic [WatchProgressEntry] at position 0 (source [WatchProgressSourceNextUp]),
 * so the existing Continue Watching cards and resume path play it from the start unchanged.
 */
const val WatchProgressSourceNextUp = "nuvio_next_up"

/** How many series are resolved per refresh (each one is a metadata fetch, cached after the first). */
const val ContinueWatchingNextUpResolveLimit = 20

data class ContinueWatchingNextUpSeed(
    val contentType: String,
    val contentId: String,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val markedAtEpochMs: Long,
)

val WatchProgressEntry.isContinueWatchingNextUp: Boolean
    get() = source == WatchProgressSourceNextUp

/**
 * Pure seed selection (unit-testable). Returns at most [limit] series, most recently completed first.
 */
fun buildContinueWatchingNextUpSeeds(
    progressEntries: List<WatchProgressEntry>,
    watchedItems: List<WatchedItem>,
    isProgressSeed: (WatchProgressEntry) -> Boolean,
    isDroppedShow: (contentId: String) -> Boolean,
    recencyCutoffEpochMs: Long?,
    preferFurthestEpisode: Boolean,
    dismissedNextUpKeys: Set<String>,
    limit: Int = ContinueWatchingNextUpResolveLimit,
): List<ContinueWatchingNextUpSeed> {
    val markers = buildList {
        progressEntries.forEach { entry ->
            val season = entry.seasonNumber ?: return@forEach
            val episode = entry.episodeNumber ?: return@forEach
            if (season == 0) return@forEach
            if (!entry.parentMetaType.isSeriesTypeForContinueWatching()) return@forEach
            if (isMalformedNextUpSeedContentId(entry.parentMetaId)) return@forEach
            if (!isProgressSeed(entry)) return@forEach
            add(ContinueWatchingNextUpSeed(entry.parentMetaType, entry.parentMetaId, season, episode, entry.lastUpdatedEpochMs))
        }
        watchedItems.forEach { item ->
            val season = item.season ?: return@forEach
            val episode = item.episode ?: return@forEach
            if (season == 0) return@forEach
            if (!item.type.isSeriesTypeForContinueWatching()) return@forEach
            if (isMalformedNextUpSeedContentId(item.id)) return@forEach
            add(ContinueWatchingNextUpSeed(item.type, item.id, season, episode, normalizeWatchedMarkedAtEpochMs(item.markedAtEpochMs)))
        }
    }
    val ordering = if (preferFurthestEpisode) {
        compareBy<ContinueWatchingNextUpSeed>({ it.seasonNumber }, { it.episodeNumber }, { it.markedAtEpochMs })
    } else {
        compareBy<ContinueWatchingNextUpSeed>({ it.markedAtEpochMs }, { it.seasonNumber }, { it.episodeNumber })
    }
    val latestInProgressBySeries = progressEntries
        .filter { entry -> entry.shouldTreatAsInProgressForContinueWatching() }
        .groupBy { entry -> entry.parentMetaId }
        .mapValues { (_, entries) -> entries.maxOf { entry -> entry.lastUpdatedEpochMs } }

    return markers
        .groupBy { seed -> seed.contentId }
        .mapNotNull { (_, seeds) -> seeds.maxWithOrNull(ordering) }
        .filterNot { seed -> isDroppedShow(seed.contentId) }
        .filter { seed -> recencyCutoffEpochMs == null || seed.markedAtEpochMs >= recencyCutoffEpochMs }
        .filterNot { seed ->
            val inProgressAt = latestInProgressBySeries[seed.contentId] ?: return@filterNot false
            inProgressAt >= seed.markedAtEpochMs
        }
        .filterNot { seed ->
            nextUpDismissKey(seed.contentId, seed.seasonNumber, seed.episodeNumber) in dismissedNextUpKeys
        }
        .sortedByDescending { seed -> seed.markedAtEpochMs }
        .take(limit)
}

/**
 * Pure merge (unit-testable): in-progress entries plus next-up entries for series that have no
 * in-progress card, most recent first.
 */
fun mergeContinueWatchingWithNextUp(
    inProgress: List<WatchProgressEntry>,
    nextUp: List<WatchProgressEntry>,
): List<WatchProgressEntry> {
    val seriesWithCard = inProgress.mapTo(mutableSetOf()) { entry -> entry.parentMetaId }
    val videoIds = inProgress.mapTo(mutableSetOf()) { entry -> entry.videoId }
    val extra = nextUp.filter { entry ->
        entry.parentMetaId !in seriesWithCard && videoIds.add(entry.videoId)
    }
    if (extra.isEmpty()) return inProgress
    return (inProgress + extra).sortedByDescending { entry -> entry.lastUpdatedEpochMs }
}

object ContinueWatchingNextUp {
    private val lock = SynchronizedObject()
    /** videoId of each resolved next-up entry → its dismiss key (seed episode, as mobile keys it). */
    private var dismissKeysByVideoId: Map<String, String> = emptyMap()

    /**
     * Resolves the next-up entries for the active profile and progress source. A failed metadata
     * fetch just leaves that series out of this refresh. `@Throws` so nothing unexpected can abort
     * the process when called from Swift (`try await`).
     */
    @Throws(Throwable::class)
    suspend fun resolveEntries(limit: Int): List<WatchProgressEntry> {
        WatchProgressRepository.ensureLoaded()
        WatchedRepository.ensureLoaded()
        ContinueWatchingPreferencesRepository.ensureLoaded()
        TraktSettingsRepository.ensureLoaded()

        val prefs = ContinueWatchingPreferencesRepository.uiState.value
        val now = WatchProgressClock.nowEpochMs()
        val entries = WatchProgressRepository.nextUpSourceEntries()
        val watchedItems = if (WatchProgressRepository.isTraktProgressActive()) {
            emptyList()
        } else {
            WatchedRepository.uiState.value.items
        }
        val seeds = buildContinueWatchingNextUpSeeds(
            progressEntries = entries,
            watchedItems = watchedItems,
            isProgressSeed = { entry -> WatchProgressRepository.shouldUseAsNextUpSeed(entry, now) },
            isDroppedShow = { contentId -> WatchProgressRepository.isDroppedShow(contentId) },
            recencyCutoffEpochMs = WatchProgressRepository.activeProviderContinueWatchingCutoffEpochMs(
                daysCap = TraktSettingsRepository.uiState.value.continueWatchingDaysCap,
                nowEpochMs = now,
            ),
            preferFurthestEpisode = prefs.upNextFromFurthestEpisode,
            dismissedNextUpKeys = prefs.dismissedNextUpKeys,
            limit = limit,
        )
        if (seeds.isEmpty()) {
            synchronized(lock) { dismissKeysByVideoId = emptyMap() }
            return emptyList()
        }
        val todayIsoDate = CurrentDateProvider.todayIsoDate()
        val resolved = coroutineScope {
            seeds.map { seed ->
                async {
                    resolveSeed(
                        seed = seed,
                        entries = entries,
                        watchedItems = watchedItems,
                        todayIsoDate = todayIsoDate,
                        preferFurthestEpisode = prefs.upNextFromFurthestEpisode,
                        showUnairedNextUp = prefs.showUnairedNextUp,
                    )
                }
            }.awaitAll()
        }.filterNotNull()
        synchronized(lock) {
            dismissKeysByVideoId = resolved.associate { (entry, key) -> entry.videoId to key }
        }
        return resolved.map { (entry, _) -> entry }
    }

    /**
     * Continue Watching › Remove for any card: a next-up card is dismissed (profile-synced, the
     * series comes back once a later episode is finished); a real progress card clears its progress.
     */
    fun removeFromContinueWatching(entry: WatchProgressEntry) {
        if (entry.isContinueWatchingNextUp) {
            val key = synchronized(lock) { dismissKeysByVideoId[entry.videoId] } ?: return
            ContinueWatchingPreferencesRepository.addDismissedNextUpKey(key)
        } else {
            WatchProgressRepository.clearProgress(videoId = entry.videoId, parentMetaId = entry.parentMetaId)
        }
    }

    private suspend fun resolveSeed(
        seed: ContinueWatchingNextUpSeed,
        entries: List<WatchProgressEntry>,
        watchedItems: List<WatchedItem>,
        todayIsoDate: String,
        preferFurthestEpisode: Boolean,
        showUnairedNextUp: Boolean,
    ): Pair<WatchProgressEntry, String>? {
        return try {
            val meta = MetaDetailsRepository.fetch(type = seed.contentType, id = seed.contentId)
                ?: return null
            val preparedEntries = WatchProgressRepository.prepareNextUpProgressEntries(entries, seed.contentId)
            val action = meta.seriesPrimaryAction(
                entries = preparedEntries,
                watchedItems = watchedItems,
                todayIsoDate = todayIsoDate,
                preferFurthestEpisode = preferFurthestEpisode,
                showUnairedNextUp = showUnairedNextUp,
                allowRewatch = false,
            ) ?: return null
            // A resume action means an episode is already in progress: its own card covers it.
            if (action.resumePositionMs != null) return null
            val season = action.seasonNumber ?: return null
            val episode = action.episodeNumber ?: return null
            // The seed episode itself is never "next".
            if (season == seed.seasonNumber && episode == seed.episodeNumber) return null
            val entry = WatchProgressEntry(
                contentType = meta.type,
                parentMetaId = meta.id,
                parentMetaType = meta.type,
                videoId = action.videoId,
                title = meta.name,
                logo = meta.logo,
                poster = meta.poster,
                background = meta.background,
                seasonNumber = season,
                episodeNumber = episode,
                episodeTitle = action.episodeTitle,
                episodeThumbnail = action.episodeThumbnail,
                lastPositionMs = 0L,
                durationMs = 0L,
                lastUpdatedEpochMs = seed.markedAtEpochMs,
                isCompleted = false,
                source = WatchProgressSourceNextUp,
            )
            entry to nextUpDismissKey(seed.contentId, seed.seasonNumber, seed.episodeNumber)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            null
        }
    }
}
