package com.nuvio.app.features.watchprogress

import co.touchlab.kermit.Logger
import com.nuvio.app.features.details.MetaDetailsRepository
import com.nuvio.app.features.details.MetaVideo
import com.nuvio.app.features.details.isReleasedBy
import com.nuvio.app.features.details.seriesPrimaryAction
import com.nuvio.app.features.profiles.ProfileRepository
import com.nuvio.app.features.tracking.WatchProgressSource
import com.nuvio.app.features.trakt.TraktSettingsRepository
import com.nuvio.app.features.watched.WatchedItem
import com.nuvio.app.features.watched.WatchedRepository
import com.nuvio.app.features.watched.normalizeWatchedMarkedAtEpochMs
import com.nuvio.app.features.watching.domain.WatchingContentRef
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/**
 * tvOS "Up Next" for the Home Continue Watching row (FEAT-85, based on erdist's patch, GitHub #11).
 *
 * The shared row ([buildContinueWatchingRowEntries]) only lists titles that are started and not
 * finished, so a series drops out of the row as soon as an episode ends. Mobile fills the gap inside
 * composeApp's `HomeScreen.kt` (next-up items built per series); tvOS can't use that code, so this
 * is the same idea in :shared:
 *
 * 1. Seeds: per series, the latest completed episode, from watch progress (provider-aware via
 *    [WatchProgressRepository.shouldUseAsNextUpSeed]) plus watched history (not under Trakt, where
 *    mobile leaves local history out because Trakt's own projection carries it).
 * 2. A series is skipped when it already has an in-progress episode at least as recent as that
 *    completion (the in-progress card is the right one to show), when the active provider hides it,
 *    when it is outside the provider's recency window, or when its next-up was dismissed (the same
 *    profile-synced `dismissedNextUpKeys` mobile uses, so a dismissal on either device holds on both).
 * 3. The next episode comes from the same shared `seriesPrimaryAction` Detail's Play button uses,
 *    honouring the synced "Up next from furthest episode" and "Show unaired next up" preferences.
 *
 * Each result is a synthetic [WatchProgressEntry] at position 0 (source [WatchProgressSourceNextUp]),
 * so the existing Continue Watching cards and resume path play it from the start unchanged. Nothing
 * here is persisted: the entries are rebuilt from progress, history and preferences.
 */
const val WatchProgressSourceNextUp = "nuvio_next_up"

/** How many series are resolved per refresh (each new seed is one metadata fetch). */
const val ContinueWatchingNextUpResolveLimit = 20

/** Parallel metadata fetches per refresh; mobile's `NEXT_UP_RESOLUTION_CONCURRENCY`. */
internal const val ContinueWatchingNextUpFetchConcurrency = 4

/**
 * What tvOS Home does with an Up Next episode that has not aired yet (FEAT-85 review P2-2).
 *
 * - [Drop] (current): no card. The synced "Show unaired next up" preference defaults on, and with
 *   it a caught-up show got a card whose stream picker is empty, for an episode the Upcoming row
 *   already lists with its air date.
 * - [LabelAirDate] (not built yet): keep the card, badge it "Airs <date>" and open Detail on press.
 *   Flipping [ContinueWatchingUnairedNextUpPolicy] keeps the card; the badge and the press route
 *   are Swift work in `ContinueWatchingRow` / `HomeRowActions` that has to land with the flip.
 */
enum class UnairedNextUpPolicy { Drop, LabelAirDate }

/** The one switch for the rule above. */
val ContinueWatchingUnairedNextUpPolicy: UnairedNextUpPolicy = UnairedNextUpPolicy.Drop

/** Pure (unit-tested): whether an Up Next episode gets a card under [policy]. */
fun keepNextUpEpisode(isReleased: Boolean, policy: UnairedNextUpPolicy): Boolean =
    isReleased || policy == UnairedNextUpPolicy.LabelAirDate

/**
 * Pure (unit-tested): the episode a `seriesPrimaryAction` result points at, as mobile's
 * `videoForSeriesAction` finds it: by season and episode first, then by playback id.
 */
fun nextUpVideoFor(
    videos: List<MetaVideo>,
    contentId: String,
    seasonNumber: Int?,
    episodeNumber: Int?,
    videoId: String,
): MetaVideo? {
    if (seasonNumber != null && episodeNumber != null) {
        videos.firstOrNull { video -> video.season == seasonNumber && video.episode == episodeNumber }
            ?.let { return it }
    }
    return videos.firstOrNull { video ->
        video.id == videoId || buildPlaybackVideoId(
            parentMetaId = contentId,
            seasonNumber = video.season,
            episodeNumber = video.episode,
            fallbackVideoId = video.id,
        ) == videoId
    }
}

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
 * Pure seed selection (unit-tested). Returns at most [limit] series, most recently completed first.
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
    // The same two orderings as the shared `latestCompletedSeriesEpisode` mobile seeds from.
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
        // Mobile's `shouldTreatAsActiveInProgressForNextUpSuppression`: `>=`, so a tie keeps the
        // in-progress card.
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
 * Pure merge (unit-tested), mobile's `buildHomeContinueWatchingItems` rule: one card per series,
 * the more recent of its in-progress entry and its next-up wins, and an in-progress entry wins a
 * tie. So an episode abandoned half way keeps its card until a LATER episode is finished, and the
 * card for an Up Next the user starts playing turns into that episode's progress card at once
 * (its progress is newer than the completion the Up Next was dated from).
 *
 * Returns [inProgress] itself when there is nothing to merge, so Home's structural compare sees an
 * unchanged row and does not republish.
 */
fun mergeContinueWatchingWithNextUp(
    inProgress: List<WatchProgressEntry>,
    nextUp: List<WatchProgressEntry>,
): List<WatchProgressEntry> {
    if (nextUp.isEmpty()) return inProgress
    val seen = mutableSetOf<String>()
    return (inProgress.map { it to true } + nextUp.map { it to false })
        .sortedWith(
            compareByDescending<Pair<WatchProgressEntry, Boolean>> { (entry, _) -> entry.lastUpdatedEpochMs }
                .thenByDescending { (_, isProgress) -> isProgress },
        )
        .filter { (entry, _) -> seen.add(entry.parentMetaId.ifBlank { entry.videoId }) }
        .map { (entry, _) -> entry }
}

/**
 * Pure (unit-tested): drops the next-up entries whose dismiss key is now in [dismissedNextUpKeys].
 * Home applies it the moment the preferences change, so a removed Up Next card leaves the row at
 * once instead of after the next resolution.
 */
fun withoutDismissedNextUp(
    entries: List<WatchProgressEntry>,
    dismissKeyByVideoId: Map<String, String>,
    dismissedNextUpKeys: Set<String>,
): List<WatchProgressEntry> = entries.filterNot { entry ->
    entry.isContinueWatchingNextUp && dismissKeyByVideoId[entry.videoId] in dismissedNextUpKeys
}

/**
 * The inputs a seed's resolution depends on besides the episode metadata. Two refreshes with the
 * same key give the same next episode, so the result is reused instead of refetched; the date is
 * in it so an episode that airs overnight is picked up the next day. The profile is in it so a
 * result can never cross a profile switch, even one that lands between two refreshes.
 */
internal fun nextUpResolveKey(
    seed: ContinueWatchingNextUpSeed,
    profileId: Int,
    source: String,
    preferFurthestEpisode: Boolean,
    showUnairedNextUp: Boolean,
    todayIsoDate: String,
): String = listOf(
    source,
    seed.contentType,
    seed.contentId,
    seed.seasonNumber.toString(),
    seed.episodeNumber.toString(),
    if (preferFurthestEpisode) "furthest" else "latest",
    if (showUnairedNextUp) "unaired" else "aired",
    todayIsoDate,
).joinToString("|", prefix = "p$profileId|")

object ContinueWatchingNextUp {
    private val log = Logger.withTag("CWNextUp")
    private val lock = SynchronizedObject()

    /** videoId of each resolved next-up entry → its dismiss key (seed episode, as mobile keys it). */
    private var dismissKeysByVideoId: Map<String, String> = emptyMap()

    /**
     * Conclusive results of the last refresh by [nextUpResolveKey]; a null value is a settled "no
     * next episode" (series finished, next one unaired). Only the current seeds' keys are kept, so
     * the map never outgrows [ContinueWatchingNextUpResolveLimit]. A failed fetch is not stored and
     * is retried on the next refresh.
     */
    private var resolvedByKey: Map<String, WatchProgressEntry?> = emptyMap()

    /** Bumped by [clearLocalState]; a refresh that started before it does not write back. */
    private var generation = 0L

    /** Last logged summary, so the probe line prints once per change, not once per refresh. */
    private var lastSummary: String? = null

    /**
     * One refresh at a time. Home cancels its Swift task on every new trigger, but a Swift cancel
     * does not reach a running Kotlin call; serialising means an overlapping refresh waits and then
     * finds the first one's results in [resolvedByKey] instead of fetching the same series again.
     */
    private val resolveMutex = Mutex()

    /**
     * Resolves the next-up entries for the active profile and progress source. The work runs on
     * `Dispatchers.Default` (Home calls this from the main actor). A failed metadata fetch just
     * leaves that series out of this refresh. `@Throws` so nothing unexpected can abort the process
     * when called from Swift (`try await`).
     */
    @Throws(Throwable::class)
    suspend fun resolveEntries(limit: Int): List<WatchProgressEntry> {
        WatchProgressRepository.ensureLoaded()
        WatchedRepository.ensureLoaded()
        ContinueWatchingPreferencesRepository.ensureLoaded()
        TraktSettingsRepository.ensureLoaded()
        return withContext(Dispatchers.Default) { resolveMutex.withLock { resolve(limit) } }
    }

    private suspend fun resolve(limit: Int): List<WatchProgressEntry> {
        val startGeneration = synchronized(lock) { generation }
        val profileId = ProfileRepository.activeProfileId
        val prefs = ContinueWatchingPreferencesRepository.uiState.value
        val now = WatchProgressClock.nowEpochMs()
        val source = WatchProgressRepository.activeSourceState.value
        // The published projection (the same list mobile's Home reads), not a private snapshot.
        val entries = WatchProgressRepository.uiState.value.entries
        val watchedItems = if (source == WatchProgressSource.TRAKT) {
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
        val todayIsoDate = CurrentDateProvider.todayIsoDate()
        val known = synchronized(lock) { resolvedByKey }
        val semaphore = Semaphore(ContinueWatchingNextUpFetchConcurrency)
        val outcomes = coroutineScope {
            seeds.map { seed ->
                val key = nextUpResolveKey(
                    seed = seed,
                    profileId = profileId,
                    source = source.name,
                    preferFurthestEpisode = prefs.upNextFromFurthestEpisode,
                    showUnairedNextUp = prefs.showUnairedNextUp,
                    todayIsoDate = todayIsoDate,
                )
                async {
                    if (known.containsKey(key)) {
                        // Same seed episode, possibly re-finished: keep the card dated from it.
                        SeedOutcome(seed, key, known[key]?.copy(lastUpdatedEpochMs = seed.markedAtEpochMs), conclusive = true, fetched = false)
                    } else {
                        semaphore.withPermit {
                            resolveSeed(
                                seed = seed,
                                key = key,
                                entries = entries,
                                watchedItems = watchedItems,
                                todayIsoDate = todayIsoDate,
                                preferFurthestEpisode = prefs.upNextFromFurthestEpisode,
                                showUnairedNextUp = prefs.showUnairedNextUp,
                            )
                        }
                    }
                }
            }.awaitAll()
        }
        val resolved = outcomes.mapNotNull { outcome -> outcome.entry?.let { entry -> entry to outcome.seed } }
        synchronized(lock) {
            if (generation != startGeneration) return emptyList()
            resolvedByKey = outcomes.filter { it.conclusive }.associate { it.key to it.entry }
            dismissKeysByVideoId = resolved.associate { (entry, seed) ->
                entry.videoId to nextUpDismissKey(seed.contentId, seed.seasonNumber, seed.episodeNumber)
            }
            // Probe line for the console stream / rig: one per change in what Up Next shows.
            val summary = "seeds=${seeds.size} cards=${resolved.size} " +
                "fetched=${outcomes.count { it.fetched }} failed=${outcomes.count { !it.conclusive }} " +
                "source=${source.name} ids=${resolved.joinToString(",") { (entry, _) -> entry.videoId }}"
            if (summary != lastSummary) {
                lastSummary = summary
                log.i { "upnext $summary" }
            }
        }
        return resolved.map { (entry, _) -> entry }
    }

    /** The dismiss keys of the entries the last refresh returned, for [withoutDismissedNextUp]. */
    fun dismissKeysSnapshot(): Map<String, String> = synchronized(lock) { dismissKeysByVideoId }

    /** [withoutDismissedNextUp] against the current preferences and the last refresh's keys. */
    fun withoutDismissed(entries: List<WatchProgressEntry>): List<WatchProgressEntry> =
        withoutDismissedNextUp(
            entries = entries,
            dismissKeyByVideoId = dismissKeysSnapshot(),
            dismissedNextUpKeys = ContinueWatchingPreferencesRepository.uiState.value.dismissedNextUpKeys,
        )

    /**
     * Continue Watching › Remove for any card: a next-up card is dismissed (profile-synced; the
     * series comes back once a later episode is finished, because playing any of its episodes
     * clears its keys in `WatchProgressRepository.upsert`); a real progress card clears its progress.
     */
    fun removeFromContinueWatching(entry: WatchProgressEntry) {
        if (entry.isContinueWatchingNextUp) {
            val key = synchronized(lock) { dismissKeysByVideoId[entry.videoId] } ?: return
            ContinueWatchingPreferencesRepository.addDismissedNextUpKey(key)
        } else {
            WatchProgressRepository.clearProgress(videoId = entry.videoId, parentMetaId = entry.parentMetaId)
        }
    }

    /**
     * Profile switch (`TvOsProviderInstaller`'s profile fan-out, next to the Upcoming row's step):
     * the same reset as the account wipe. The generation bump means a refresh still running for
     * the outgoing profile cannot write its results or dismiss keys back afterwards.
     */
    fun onProfileChanged() = clearLocalState()

    /** Account wipe (`TvOsAccountDataCleaner`): the cached results name the outgoing account's shows. */
    fun clearLocalState() {
        synchronized(lock) {
            generation += 1
            resolvedByKey = emptyMap()
            dismissKeysByVideoId = emptyMap()
            lastSummary = null
        }
    }

    private class SeedOutcome(
        val seed: ContinueWatchingNextUpSeed,
        val key: String,
        val entry: WatchProgressEntry?,
        /** False for a failed fetch: not cached, retried on the next refresh. */
        val conclusive: Boolean,
        val fetched: Boolean,
    )

    private suspend fun resolveSeed(
        seed: ContinueWatchingNextUpSeed,
        key: String,
        entries: List<WatchProgressEntry>,
        watchedItems: List<WatchedItem>,
        todayIsoDate: String,
        preferFurthestEpisode: Boolean,
        showUnairedNextUp: Boolean,
    ): SeedOutcome {
        fun settled(entry: WatchProgressEntry?) = SeedOutcome(seed, key, entry, conclusive = true, fetched = true)
        return try {
            // `cacheResult = false`: a bulk caller, like the Upcoming sweep. Results are reused
            // through `resolvedByKey` instead, so a seed is fetched once until it changes.
            val meta = MetaDetailsRepository.fetch(type = seed.contentType, id = seed.contentId, cacheResult = false)
                ?: return SeedOutcome(seed, key, null, conclusive = false, fetched = true)
            val preparedEntries = WatchProgressRepository.prepareNextUpProgressEntries(entries, seed.contentId)
            // The seed's own content ref, as mobile passes `completedEntry.content`: an add-on can
            // answer with an aliased meta id (a tmdb: id for a tt one), and the user's progress,
            // the dismiss key and the in-progress dedup are all keyed by the id they watched under.
            val content = WatchingContentRef(type = seed.contentType, id = seed.contentId)
            val action = meta.seriesPrimaryAction(
                content = content,
                entries = preparedEntries,
                watchedItems = watchedItems,
                todayIsoDate = todayIsoDate,
                preferFurthestEpisode = preferFurthestEpisode,
                showUnairedNextUp = showUnairedNextUp,
                allowRewatch = false,
            ) ?: return settled(null)
            // A resume action means an episode is already in progress: its own card covers it.
            if (action.resumePositionMs != null) return settled(null)
            val season = action.seasonNumber ?: return settled(null)
            val episode = action.episodeNumber ?: return settled(null)
            // The seed episode itself is never "next".
            if (season == seed.seasonNumber && episode == seed.episodeNumber) return settled(null)
            // P2-2: an episode that has not aired gets no card (see [UnairedNextUpPolicy]). No
            // matching video at all is no card either, as on mobile.
            val video = nextUpVideoFor(meta.videos, seed.contentId, season, episode, action.videoId)
                ?: return settled(null)
            if (!keepNextUpEpisode(video.isReleasedBy(todayIsoDate), ContinueWatchingUnairedNextUpPolicy)) {
                return settled(null)
            }
            settled(
                WatchProgressEntry(
                    contentType = seed.contentType,
                    parentMetaId = seed.contentId,
                    parentMetaType = seed.contentType,
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
                ),
            )
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            log.w { "upnext resolve failed for ${seed.contentId}: ${error.message}" }
            SeedOutcome(seed, key, null, conclusive = false, fetched = true)
        }
    }
}
