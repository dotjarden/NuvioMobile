package com.nuvio.app.features.trakt

import kotlin.concurrent.Volatile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/*
 * BUG-220: a write-ahead queue for Trakt `/scrobble/stop`.
 *
 * With Watch Progress Source = Trakt the read side hides every local row Trakt can represent
 * (`WatchProgressSourceProjection`), so after a relaunch a resume position exists only if the
 * session's single `/scrobble/stop` reached Trakt. That request used to be fire-and-forget: no
 * auth yet, a profile change mid-flight, a 5xx after the retries, being offline, or the app being
 * killed before it landed all dropped it silently.
 *
 * Now every stop is persisted BEFORE it is sent, deleted once Trakt answers 2xx/409 (or rejects it
 * for good), and replayed later when it did not land: at profile selection (every launch enters
 * through it) and whenever Trakt auth becomes available. Only stops are ever replayed, never
 * starts, so nothing reopens a "watching" session; the queue is bounded per profile and by age so a
 * removal made on Trakt is not resurrected by an old entry.
 */

/** Serializable snapshot of a [TraktScrobbleItem] (the sealed item itself is not serializable). */
@Serializable
data class TraktPendingScrobbleItem(
    val kind: String,
    val title: String? = null,
    val year: Int? = null,
    val trakt: Int? = null,
    val imdb: String? = null,
    val tmdb: Int? = null,
    val slug: String? = null,
    val season: Int? = null,
    val number: Int? = null,
    val episodeTitle: String? = null,
) {
    fun toScrobbleItem(): TraktScrobbleItem? {
        val ids = TraktExternalIds(trakt = trakt, imdb = imdb, tmdb = tmdb, slug = slug)
        if (!ids.hasAnyId()) return null
        return when (kind) {
            KIND_MOVIE -> TraktScrobbleItem.Movie(title = title, year = year, ids = ids)
            KIND_EPISODE -> TraktScrobbleItem.Episode(
                showTitle = title,
                showYear = year,
                showIds = ids,
                season = season ?: return null,
                number = number ?: return null,
                episodeTitle = episodeTitle,
            )
            else -> null
        }
    }

    companion object {
        const val KIND_MOVIE = "movie"
        const val KIND_EPISODE = "episode"

        fun from(item: TraktScrobbleItem): TraktPendingScrobbleItem = when (item) {
            is TraktScrobbleItem.Movie -> TraktPendingScrobbleItem(
                kind = KIND_MOVIE,
                title = item.title,
                year = item.year,
                trakt = item.ids.trakt,
                imdb = item.ids.imdb,
                tmdb = item.ids.tmdb,
                slug = item.ids.slug,
            )
            is TraktScrobbleItem.Episode -> TraktPendingScrobbleItem(
                kind = KIND_EPISODE,
                title = item.showTitle,
                year = item.showYear,
                trakt = item.showIds.trakt,
                imdb = item.showIds.imdb,
                tmdb = item.showIds.tmdb,
                slug = item.showIds.slug,
                season = item.season,
                number = item.number,
                episodeTitle = item.episodeTitle,
            )
        }
    }
}

/** One persisted stop. [attempts] counts HTTP failures only (being offline is not the entry's fault). */
@Serializable
data class TraktPendingScrobbleStop(
    val id: String,
    val profileId: Int,
    val itemKey: String,
    val item: TraktPendingScrobbleItem,
    val progress: Float,
    val createdAtMs: Long,
    val attempts: Int = 0,
)

/**
 * The persisted per-profile list. Every mutation is a fresh read-modify-write under one mutex, and
 * updates touch only entries still present, so a sign-out wipe that lands mid-drain is never
 * written back.
 */
class TraktPendingScrobbleStopQueue(
    private val load: (profileId: Int) -> String?,
    private val save: (profileId: Int, payload: String) -> Unit,
    private val clear: (profileId: Int) -> Unit,
    private val now: () -> Long,
    val maxPerProfile: Int = DEFAULT_MAX_PER_PROFILE,
    val maxAgeMs: Long = DEFAULT_MAX_AGE_MS,
) {
    private val mutex = Mutex()
    private val serializer = ListSerializer(TraktPendingScrobbleStop.serializer())

    /**
     * Persists [stop]. An older entry for the same item and profile is superseded (a replayed old
     * stop must never overwrite a newer position); expired entries are pruned; at most
     * [maxPerProfile] newest entries are kept.
     */
    suspend fun enqueue(stop: TraktPendingScrobbleStop) = mutex.withLock {
        val kept = read(stop.profileId)
            .filterNot { it.itemKey == stop.itemKey }
            .let { prune(it) }
        write(stop.profileId, (kept + stop).sortedBy { it.createdAtMs }.takeLast(maxPerProfile))
    }

    /** The profile's live entries, oldest first. Persists the pruning when anything expired. */
    suspend fun pending(profileId: Int): List<TraktPendingScrobbleStop> = mutex.withLock {
        val stored = read(profileId)
        val pruned = prune(stored).sortedBy { it.createdAtMs }
        if (pruned.size != stored.size) write(profileId, pruned)
        pruned
    }

    suspend fun contains(profileId: Int, id: String): Boolean = mutex.withLock {
        read(profileId).any { it.id == id }
    }

    suspend fun remove(profileId: Int, id: String) = mutex.withLock {
        val stored = read(profileId)
        val remaining = stored.filterNot { it.id == id }
        if (remaining.size != stored.size) write(profileId, remaining)
    }

    /** Counts one HTTP failure; drops the entry once it reaches [maxAttempts]. True when kept. */
    suspend fun recordFailedAttempt(profileId: Int, id: String, maxAttempts: Int): Boolean = mutex.withLock {
        val stored = read(profileId)
        val entry = stored.firstOrNull { it.id == id } ?: return@withLock false
        val attempts = entry.attempts + 1
        val keep = attempts < maxAttempts
        val updated = if (keep) {
            stored.map { if (it.id == id) it.copy(attempts = attempts) else it }
        } else {
            stored.filterNot { it.id == id }
        }
        write(profileId, updated)
        keep
    }

    suspend fun clearProfile(profileId: Int) = mutex.withLock { clear(profileId) }

    private fun prune(entries: List<TraktPendingScrobbleStop>): List<TraktPendingScrobbleStop> {
        val cutoff = now() - maxAgeMs
        return entries.filter { it.createdAtMs >= cutoff }
    }

    private fun read(profileId: Int): List<TraktPendingScrobbleStop> {
        val raw = load(profileId)?.takeIf(String::isNotBlank) ?: return emptyList()
        return try {
            json.decodeFromString(serializer, raw).filter { it.profileId == profileId }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // An undecodable payload can never be replayed; drop it rather than fail forever.
            clear(profileId)
            emptyList()
        }
    }

    private fun write(profileId: Int, entries: List<TraktPendingScrobbleStop>) {
        if (entries.isEmpty()) clear(profileId) else save(profileId, json.encodeToString(serializer, entries))
    }

    companion object {
        const val DEFAULT_MAX_PER_PROFILE = 10
        const val DEFAULT_MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000
        private val json = Json { ignoreUnknownKeys = true }
    }
}

/** What one `/scrobble/stop` attempt came to, as far as the queue is concerned. */
enum class TraktScrobbleDelivery {
    /** 2xx or 409 (already scrobbled): delete the entry. */
    SENT,

    /** Deduped against an identical stop that was just delivered: delete the entry. */
    SKIPPED,

    /** No Trakt auth for the profile yet, or the profile is no longer active: keep, try later. */
    NOT_READY,

    /** Transport failure (offline, timeout): keep without counting an attempt; stop draining. */
    OFFLINE,

    /** 5xx, 401/403/408/420/423/429: keep and count an attempt; stop draining. */
    RETRYABLE,

    /** Any other 4xx (400, 404, 422 below 1 %): the request can never succeed; delete it. */
    REJECTED,
}

/** Maps a non-success HTTP status to [TraktScrobbleDelivery.RETRYABLE] or [TraktScrobbleDelivery.REJECTED]. */
fun classifyTraktScrobbleFailure(status: Int): TraktScrobbleDelivery = when (status) {
    in 500..599, 401, 403, 408, 420, 423, 429 -> TraktScrobbleDelivery.RETRYABLE
    else -> TraktScrobbleDelivery.REJECTED
}

data class TraktPendingStopDrainResult(
    val sent: Int = 0,
    val kept: Int = 0,
    val dropped: Int = 0,
)

/**
 * The write-ahead send and the replay, free of HTTP and singletons so it is unit tested
 * (`TraktPendingScrobbleStopsTest`). [deliver] is `TraktScrobbleRepository`'s request code.
 */
class TraktScrobbleStopOutbox(
    private val queue: TraktPendingScrobbleStopQueue,
    private val activeProfileId: () -> Int,
    private val isConnected: (profileId: Int) -> Boolean,
    private val now: () -> Long,
    private val newId: () -> String,
    private val log: (String) -> Unit = {},
    val maxReplayAttempts: Int = DEFAULT_MAX_REPLAY_ATTEMPTS,
) {
    private val drainMutex = Mutex()

    // The item a live `start` opened and no `stop` closed yet: the drain leaves its old entry
    // alone so a replay cannot end the session that is playing right now.
    @Volatile
    private var openSession: Pair<Int, String>? = null

    fun onSessionStarted(profileId: Int, itemKey: String) {
        openSession = profileId to itemKey
    }

    fun onProfileChanged() {
        openSession = null
    }

    /**
     * Persists the stop, then sends it. Only sent, never queued: a profile with no Trakt account
     * connected (queueing would replay its viewing into whatever account is connected next), and
     * stops below 1 %, which Trakt rejects (422) and which exist to close the "watching" session,
     * something a later replay cannot do.
     */
    suspend fun sendStop(
        profileId: Int,
        item: TraktScrobbleItem,
        progress: Float,
        deliver: suspend (TraktScrobbleItem, Float) -> TraktScrobbleDelivery,
    ): TraktScrobbleDelivery {
        if (openSession == (profileId to item.itemKey)) openSession = null
        if (progress < MIN_QUEUED_PROGRESS || !isConnected(profileId)) return deliver(item, progress)
        val entry = TraktPendingScrobbleStop(
            id = newId(),
            profileId = profileId,
            itemKey = item.itemKey,
            item = TraktPendingScrobbleItem.from(item),
            progress = progress,
            createdAtMs = now(),
        )
        queue.enqueue(entry)
        log("Trakt pending stop queued id=${entry.id} profile=$profileId item=${entry.itemKey} progress=${formatProgress(progress)}")
        val result = deliver(item, progress)
        resolve(entry, result, replay = false)
        return result
    }

    /** Replays [profileId]'s pending stops, oldest first, while that profile stays active. */
    suspend fun drain(
        profileId: Int,
        deliver: suspend (TraktScrobbleItem, Float) -> TraktScrobbleDelivery,
    ): TraktPendingStopDrainResult {
        if (activeProfileId() != profileId) return TraktPendingStopDrainResult()
        return drainMutex.withLock {
            var sent = 0
            var dropped = 0
            val entries = queue.pending(profileId)
            if (entries.isNotEmpty()) log("Trakt pending stop replay: ${entries.size} pending for profile $profileId")
            for (entry in entries) {
                if (activeProfileId() != profileId) break
                if (openSession == (profileId to entry.itemKey)) continue
                // A live stop for the same item may have superseded this entry since the snapshot.
                if (!queue.contains(profileId, entry.id)) continue
                val item = entry.item.toScrobbleItem()
                if (item == null) {
                    queue.remove(profileId, entry.id)
                    dropped += 1
                    continue
                }
                val result = deliver(item, entry.progress)
                when (resolve(entry, result, replay = true)) {
                    Resolution.REMOVED_SENT -> sent += 1
                    Resolution.REMOVED_DROPPED -> dropped += 1
                    Resolution.KEPT -> Unit
                }
                if (result == TraktScrobbleDelivery.NOT_READY ||
                    result == TraktScrobbleDelivery.OFFLINE ||
                    result == TraktScrobbleDelivery.RETRYABLE
                ) {
                    break
                }
            }
            val kept = queue.pending(profileId).size
            TraktPendingStopDrainResult(sent = sent, kept = kept, dropped = dropped)
        }
    }

    suspend fun clearProfile(profileId: Int) = queue.clearProfile(profileId)

    private enum class Resolution { REMOVED_SENT, REMOVED_DROPPED, KEPT }

    private suspend fun resolve(
        entry: TraktPendingScrobbleStop,
        result: TraktScrobbleDelivery,
        replay: Boolean,
    ): Resolution {
        val stage = if (replay) "replayed" else "live"
        return when (result) {
            TraktScrobbleDelivery.SENT, TraktScrobbleDelivery.SKIPPED -> {
                queue.remove(entry.profileId, entry.id)
                log("Trakt pending stop $stage ok id=${entry.id} result=$result (removed)")
                Resolution.REMOVED_SENT
            }
            TraktScrobbleDelivery.REJECTED -> {
                queue.remove(entry.profileId, entry.id)
                log("Trakt pending stop $stage rejected id=${entry.id} (dropped)")
                Resolution.REMOVED_DROPPED
            }
            TraktScrobbleDelivery.NOT_READY, TraktScrobbleDelivery.OFFLINE -> {
                log("Trakt pending stop $stage deferred id=${entry.id} result=$result (kept)")
                Resolution.KEPT
            }
            TraktScrobbleDelivery.RETRYABLE -> {
                val kept = queue.recordFailedAttempt(entry.profileId, entry.id, maxReplayAttempts)
                log("Trakt pending stop $stage failed id=${entry.id} (${if (kept) "kept" else "dropped after $maxReplayAttempts attempts"})")
                if (kept) Resolution.KEPT else Resolution.REMOVED_DROPPED
            }
        }
    }

    private fun formatProgress(progress: Float): String {
        val tenths = (progress * 10).toInt()
        return "${tenths / 10}.${tenths % 10}%"
    }

    companion object {
        const val DEFAULT_MAX_REPLAY_ATTEMPTS = 5
        const val MIN_QUEUED_PROGRESS = 1f
    }
}
