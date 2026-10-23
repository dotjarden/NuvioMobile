package com.nuvio.app.features.trakt

import co.touchlab.kermit.Logger
import com.nuvio.app.core.build.AppVersionConfig
import com.nuvio.app.core.profile.ActiveProfileProvider
import com.nuvio.app.features.addons.httpRequestRaw
import com.nuvio.app.features.tracking.TrackingMediaKind
import com.nuvio.app.features.tracking.TrackingMediaReference
import com.nuvio.app.features.tracking.TrackingProviderId
import com.nuvio.app.features.tracking.TrackingProviderRegistry
import com.nuvio.app.features.tracking.TrackingScrobbleAction
import com.nuvio.app.features.tracking.TrackingScrobbleEvent
import com.nuvio.app.features.tracking.TrackingScrobbler
import com.nuvio.app.features.tracking.TrackingSeekScrobblePolicy
import com.nuvio.app.core.coroutines.uncaughtCoroutineLogger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.math.abs
import kotlin.random.Random

private const val BASE_URL = "https://api.trakt.tv"

sealed interface TraktScrobbleItem {
    val itemKey: String

    data class Movie(
        val title: String?,
        val year: Int?,
        val ids: TraktExternalIds,
    ) : TraktScrobbleItem {
        override val itemKey: String =
            "movie:${ids.imdb ?: ids.tmdb ?: ids.trakt ?: title.orEmpty()}:${year ?: 0}"
    }

    data class Episode(
        val showTitle: String?,
        val showYear: Int?,
        val showIds: TraktExternalIds,
        val season: Int,
        val number: Int,
        val episodeTitle: String?,
    ) : TraktScrobbleItem {
        override val itemKey: String =
            "episode:${showIds.imdb ?: showIds.tmdb ?: showIds.trakt ?: showTitle.orEmpty()}:$season:$number"
    }
}

// Fork: public (upstream: internal) — shared tests consume these cross-module.
data class TraktEpisodeMappingInput(
    val contentId: String,
    val contentType: String,
    val videoId: String?,
    val season: Int,
    val episode: Int,
    val episodeTitle: String?,
)

fun TrackingMediaReference.toTraktEpisodeMappingInput(): TraktEpisodeMappingInput? {
    val episodeReference = episode ?: return null
    val season = episodeReference.season ?: return null
    val contentId = catalog?.contentId?.takeIf(String::isNotBlank)
        ?: ids.imdb?.takeIf(String::isNotBlank)
        ?: ids.tmdb?.let { value -> "tmdb:$value" }
        ?: ids.trakt?.let { value -> "trakt:$value" }
        ?: return null
    return TraktEpisodeMappingInput(
        contentId = contentId,
        contentType = catalog?.contentType?.takeIf(String::isNotBlank) ?: "series",
        videoId = catalog?.videoId?.takeIf(String::isNotBlank),
        season = season,
        episode = episodeReference.number,
        episodeTitle = episodeReference.title,
    )
}

object TraktScrobbleRepository : TrackingScrobbler {
    override val providerId: TrackingProviderId = TrackingProviderId.TRAKT
    override val seekScrobblePolicy: TrackingSeekScrobblePolicy =
        TrackingSeekScrobblePolicy.STOP_AND_RESTART

    private data class ScrobbleStamp(
        val profileId: Int,
        val action: String,
        val itemKey: String,
        val progress: Float,
        val timestampMs: Long,
    )

    private val log = Logger.withTag("TraktScrobble")
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        explicitNulls = false
    }

    private var lastScrobbleStamp: ScrobbleStamp? = null

    private val replayScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default + uncaughtCoroutineLogger("TraktScrobbleRepository"),
    )
    private var authWatcher: Job? = null

    private val pendingStops = TraktScrobbleStopOutbox(
        queue = TraktPendingScrobbleStopQueue(
            load = TraktPendingScrobbleStopStorage::load,
            save = TraktPendingScrobbleStopStorage::save,
            clear = TraktPendingScrobbleStopStorage::clear,
            now = TraktPlatformClock::nowEpochMs,
        ),
        activeProfileId = { ActiveProfileProvider.activeProfileId },
        isConnected = { profileId ->
            ActiveProfileProvider.activeProfileId == profileId && TraktAuthRepository.isAuthenticated.value
        },
        now = TraktPlatformClock::nowEpochMs,
        newId = { "${TraktPlatformClock.nowEpochMs()}-${Random.nextInt(0, Int.MAX_VALUE)}" },
        log = ::trace,
    )

    /**
     * BUG-220 queue/replay lines. Kermit goes to os_log on Apple, which the device console pipe
     * (`devicectl --console`, scripts/device/console.sh) cannot see, so these are mirrored to
     * stdout (the SubtitleRepository precedent). They carry item keys and progress, never headers.
     */
    private fun trace(message: String) {
        log.i { message }
        println("[TraktScrobble] $message")
    }
    private val minSendIntervalMs = 8_000L
    private val progressWindow = 1.5f
    private val maxStopRetries = 2
    private val retryDelayMs = 1_500L
    private val serverOverloadedRetryDelayMs = 5_000L

    init {
        TrackingProviderRegistry.registerScrobbler(this)
    }

    /** Forces this object's initializer (and therefore its registry registration) to run. */
    fun ensureRegistered() = Unit

    /**
     * Provider-neutral scrobble entry point used by [TrackingScrobbleCoordinator].
     *
     * Phase 1 note: the player still calls [scrobbleStart]/[scrobbleStop] directly, so this path
     * is the registered seam rather than the live one. Both funnel into the same [sendScrobble]
     * dedupe/retry machinery, so wiring the coordinator up later changes no Trakt behaviour.
     */
    override suspend fun scrobble(
        profileId: Int,
        action: TrackingScrobbleAction,
        event: TrackingScrobbleEvent,
    ) {
        val item = buildItem(event.media) ?: return
        sendScrobble(
            profileId = profileId,
            action = action.wireValue,
            item = item,
            progressPercent = event.progressPercent.toFloat(),
        )
    }

    private suspend fun buildItem(media: TrackingMediaReference): TraktScrobbleItem? {
        val ids = TraktExternalIds(
            trakt = media.ids.trakt?.toTraktIntOrNull(),
            imdb = media.ids.imdb?.takeIf(String::isNotBlank),
            tmdb = media.ids.tmdb?.toTraktIntOrNull(),
        )
        if (!ids.hasAnyId()) return null
        if (media.kind == TrackingMediaKind.MOVIE) {
            return TraktScrobbleItem.Movie(
                title = media.title,
                year = media.year,
                ids = ids,
            )
        }

        val mappingInput = media.toTraktEpisodeMappingInput() ?: return null
        val mappedEpisode = TraktEpisodeMappingService.resolveEpisodeMapping(
            contentId = mappingInput.contentId,
            contentType = mappingInput.contentType,
            videoId = mappingInput.videoId,
            season = mappingInput.season,
            episode = mappingInput.episode,
            episodeTitle = mappingInput.episodeTitle,
        )
        return TraktScrobbleItem.Episode(
            showTitle = media.title,
            showYear = media.year,
            showIds = ids,
            season = mappedEpisode?.season ?: mappingInput.season,
            number = mappedEpisode?.episode ?: mappingInput.episode,
            episodeTitle = mappingInput.episodeTitle,
        )
    }

    suspend fun scrobbleStart(profileId: Int, item: TraktScrobbleItem, progressPercent: Float) {
        sendScrobble(profileId = profileId, action = "start", item = item, progressPercent = progressPercent)
    }

    suspend fun scrobbleStop(profileId: Int, item: TraktScrobbleItem, progressPercent: Float) {
        sendScrobble(profileId = profileId, action = "stop", item = item, progressPercent = progressPercent)
    }

    suspend fun buildItem(
        contentType: String,
        parentMetaId: String,
        videoId: String?,
        title: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        episodeTitle: String?,
        releaseInfo: String? = null,
    ): TraktScrobbleItem? {
        val normalizedType = contentType.trim().lowercase()
        var ids = parseTraktContentIds(parentMetaId)

        // Fallback: if parentMetaId doesn't resolve to valid Trakt IDs, try videoId.
        // Some addons use non-standard contentId (e.g. "tun_tt7821582") but set a
        // valid IMDB/TMDB videoId (e.g. "tt7821582:3:7").
        if (!ids.hasAnyId() && !videoId.isNullOrBlank() && videoId != parentMetaId) {
            ids = parseTraktContentIds(videoId)
        }

        // Don't send scrobble if we still have no valid Trakt IDs — would cause
        // title-based fuzzy match on Trakt API resulting in wrong show matched.
        if (!ids.hasAnyId()) return null

        val parsedYear = extractTraktYear(releaseInfo)

        return if (
            normalizedType in listOf("series", "tv", "show", "tvshow") &&
            seasonNumber != null &&
            episodeNumber != null
        ) {
            val mappedEpisode = TraktEpisodeMappingService.resolveEpisodeMapping(
                contentId = parentMetaId,
                contentType = contentType,
                videoId = videoId,
                season = seasonNumber,
                episode = episodeNumber,
                episodeTitle = episodeTitle,
            )
            TraktScrobbleItem.Episode(
                showTitle = title,
                showYear = parsedYear,
                showIds = ids,
                season = mappedEpisode?.season ?: seasonNumber,
                number = mappedEpisode?.episode ?: episodeNumber,
                episodeTitle = episodeTitle,
            )
        } else {
            TraktScrobbleItem.Movie(
                title = title,
                year = parsedYear,
                ids = ids,
            )
        }
    }

    private suspend fun sendScrobble(
        profileId: Int,
        action: String,
        item: TraktScrobbleItem,
        progressPercent: Float,
    ) {
        val clampedProgress = progressPercent.coerceIn(0f, 100f)
        when (action) {
            // BUG-220: persisted before it is sent, replayed later if it does not land.
            "stop" -> pendingStops.sendStop(profileId, item, clampedProgress) { stopItem, progress ->
                deliver(profileId, action, stopItem, progress, replay = false)
            }
            "start" -> {
                pendingStops.onSessionStarted(profileId, item.itemKey)
                deliver(profileId, action, item, clampedProgress, replay = false)
            }
            else -> deliver(profileId, action, item, clampedProgress, replay = false)
        }
    }

    /**
     * One request. A live stop retries transport failures and 5xx in place (as before); a replay
     * sends once and leaves the retry to the next drain. A live stop refreshes Trakt progress on
     * success; a drain refreshes once at its end.
     */
    private suspend fun deliver(
        profileId: Int,
        action: String,
        item: TraktScrobbleItem,
        clampedProgress: Float,
        replay: Boolean,
    ): TraktScrobbleDelivery {
        if (ActiveProfileProvider.activeProfileId != profileId) return TraktScrobbleDelivery.NOT_READY
        val headers = TraktAuthRepository.authorizedHeaders() ?: return TraktScrobbleDelivery.NOT_READY
        if (ActiveProfileProvider.activeProfileId != profileId) return TraktScrobbleDelivery.NOT_READY
        if (!replay && shouldSkip(profileId, action, item.itemKey, clampedProgress)) {
            return TraktScrobbleDelivery.SKIPPED
        }

        val url = "$BASE_URL/scrobble/$action"
        val requestBody = json.encodeToString(buildRequestBody(item, clampedProgress))
        val requestHeaders = mapOf(
            "Accept" to "application/json",
            "Content-Type" to "application/json",
        ) + headers

        log.d {
            buildString {
                append("Trakt scrobble ")
                append(action)
                if (replay) append(" (replay)")
                append(" request")
                append('\n')
                append("url=")
                append(url)
                append('\n')
                append("headers=")
                append(requestHeaders.redactedForLogs().formatForLog())
                append('\n')
                append("body=")
                append(requestBody.ifBlank { "<empty>" })
            }
        }

        val attempts = if (action == "stop" && !replay) maxStopRetries + 1 else 1
        var wasSent = false
        for (attempt in 1..attempts) {
            val response = runCatching {
                httpRequestRaw(
                    method = "POST",
                    url = url,
                    body = requestBody,
                    headers = requestHeaders,
                )
            }.onFailure { error ->
                if (error is CancellationException) throw error
                log.w(error) {
                    "Trakt scrobble $action transport failure on attempt $attempt/$attempts"
                }
            }.getOrNull()

            if (response == null) {
                if (attempt < attempts) {
                    delay(retryDelayMs * attempt)
                    continue
                }
                return TraktScrobbleDelivery.OFFLINE
            }

            log.d {
                buildString {
                    append("Trakt scrobble ")
                    append(action)
                    append(" response")
                    append('\n')
                    append("status=")
                    append(response.status)
                    append(' ')
                    append(response.statusText.ifBlank { "<no-status-text>" })
                    append('\n')
                    append("url=")
                    append(response.url)
                    append('\n')
                    append("headers=")
                    append(response.headers.formatForLog())
                    append('\n')
                    append("body=")
                    append(response.body.ifBlank { "<empty>" })
                }
            }

            if (response.status in 200..299 || response.status == 409) {
                if (action == "stop") trace("Trakt scrobble stop status=${response.status}${if (replay) " (replay)" else ""}")
                wasSent = true
                break
            }

            if (response.status in 500..599 && attempt < attempts) {
                val delayMs = if (response.status in 502..504) serverOverloadedRetryDelayMs else retryDelayMs * attempt
                delay(delayMs)
                continue
            }

            val failure = "Failed Trakt scrobble $action: HTTP ${response.status} ${response.statusText.ifBlank { "<no-status-text>" }}"
            if (action == "stop") trace(failure) else log.w { failure }
            return classifyTraktScrobbleFailure(response.status)
        }

        if (!wasSent) return TraktScrobbleDelivery.OFFLINE

        lastScrobbleStamp = ScrobbleStamp(
            profileId = profileId,
            action = action,
            itemKey = item.itemKey,
            progress = clampedProgress,
            timestampMs = TraktPlatformClock.nowEpochMs(),
        )

        if (action == "stop" && !replay) refreshProgressAfterStop()
        return TraktScrobbleDelivery.SENT
    }

    private suspend fun refreshProgressAfterStop() {
        runCatching { TraktProgressRepository.invalidateAndRefresh() }
            .onFailure { error ->
                if (error is CancellationException) throw error
                log.w { "Failed to refresh Trakt progress after stop: ${error.message}" }
            }
    }

    // ── BUG-220 pending-stop replay ─────────────────────────────────────────────────────────

    /**
     * Profile-selection hook (tvOS fan-out after `traktAuth`, composeApp's adapter): every launch
     * enters through it, so this is the launch drain. Also arms the auth watcher once, which
     * drains again whenever Trakt auth turns on later (device-flow connect, credential sync pull).
     */
    fun onProfileChanged(profileId: Int) {
        pendingStops.onProfileChanged()
        armAuthWatcher()
        requestPendingStopReplay(profileId)
    }

    /** Drops [profileId]'s pending stops (Trakt disconnect, profile removal): never replay into another account. */
    fun clearPendingStops(profileId: Int) {
        TraktPendingScrobbleStopStorage.clear(profileId)
    }

    fun requestPendingStopReplay(profileId: Int = ActiveProfileProvider.activeProfileId) {
        replayScope.launch { replayPendingStops(profileId) }
    }

    suspend fun replayPendingStops(profileId: Int = ActiveProfileProvider.activeProfileId): TraktPendingStopDrainResult {
        val result = pendingStops.drain(profileId) { item, progress ->
            deliver(profileId, "stop", item, progress, replay = true)
        }
        if (result.sent > 0 || result.dropped > 0 || result.kept > 0) {
            trace("Trakt pending stop replay done profile=$profileId sent=${result.sent} kept=${result.kept} dropped=${result.dropped}")
        }
        if (result.sent > 0) refreshProgressAfterStop()
        return result
    }

    private fun armAuthWatcher() {
        if (authWatcher != null) return
        // drop(1): the current value is covered by the explicit request in onProfileChanged.
        authWatcher = replayScope.launch {
            TraktAuthRepository.isAuthenticated.drop(1).collect { authenticated ->
                if (authenticated) replayPendingStops(ActiveProfileProvider.activeProfileId)
            }
        }
    }

    private fun buildRequestBody(
        item: TraktScrobbleItem,
        clampedProgress: Float,
    ): TraktScrobbleRequest {
        return when (item) {
            is TraktScrobbleItem.Movie -> TraktScrobbleRequest(
                movie = TraktMovieBody(
                    title = item.title,
                    year = item.year,
                    ids = item.ids.toRequestBodyOrNull(),
                ),
                progress = clampedProgress,
                appVersion = AppVersionConfig.VERSION_NAME,
            )

            is TraktScrobbleItem.Episode -> TraktScrobbleRequest(
                show = TraktShowBody(
                    title = item.showTitle,
                    year = item.showYear,
                    ids = item.showIds.toRequestBodyOrNull(),
                ),
                episode = TraktEpisodeBody(
                    title = item.episodeTitle,
                    season = item.season,
                    number = item.number,
                ),
                progress = clampedProgress,
                appVersion = AppVersionConfig.VERSION_NAME,
            )
        }
    }

    private fun shouldSkip(profileId: Int, action: String, itemKey: String, progress: Float): Boolean {
        val last = lastScrobbleStamp ?: return false
        val now = TraktPlatformClock.nowEpochMs()
        val isSameWindow = now - last.timestampMs < minSendIntervalMs
        val isSameProfile = last.profileId == profileId
        val isSameAction = last.action == action
        val isSameItem = last.itemKey == itemKey
        val isNearProgress = abs(last.progress - progress) <= progressWindow
        if (action == "stop" && last.action == "start" && isSameItem && isSameProfile) {
            return false
        }
        return isSameWindow && isSameProfile && isSameAction && isSameItem && isNearProgress
    }

    private fun Map<String, String>.redactedForLogs(): Map<String, String> =
        entries.associate { (key, value) ->
            key to when {
                key.equals("authorization", ignoreCase = true) -> redactBearerValue(value)
                key.equals("trakt-api-key", ignoreCase = true) -> "<redacted>"
                else -> value
            }
        }

    private fun Map<String, String>.formatForLog(): String =
        entries
            .sortedBy { it.key.lowercase() }
            .joinToString(prefix = "{", postfix = "}") { (key, value) -> "$key=$value" }

    private fun redactBearerValue(value: String): String {
        val tokenPrefix = "Bearer "
        if (!value.startsWith(tokenPrefix, ignoreCase = true)) return "<redacted>"
        val token = value.removePrefix(tokenPrefix).trim()
        if (token.isBlank()) return "Bearer <redacted>"
        val prefix = token.take(6)
        val suffix = token.takeLast(4)
        return "Bearer ${prefix}...${suffix}"
    }

    private fun TraktExternalIds.toRequestBodyOrNull(): TraktIdsBody? {
        if (trakt == null && imdb.isNullOrBlank() && tmdb == null) return null
        return TraktIdsBody(
            trakt = trakt,
            imdb = imdb,
            tmdb = tmdb,
        )
    }
}

private fun Long.toTraktIntOrNull(): Int? = takeIf { value -> value in 1L..Int.MAX_VALUE.toLong() }?.toInt()

@Serializable
private data class TraktScrobbleRequest(
    @SerialName("movie") val movie: TraktMovieBody? = null,
    @SerialName("show") val show: TraktShowBody? = null,
    @SerialName("episode") val episode: TraktEpisodeBody? = null,
    @SerialName("progress") val progress: Float,
    @SerialName("app_version") val appVersion: String? = null,
)

@Serializable
private data class TraktMovieBody(
    @SerialName("title") val title: String? = null,
    @SerialName("year") val year: Int? = null,
    @SerialName("ids") val ids: TraktIdsBody? = null,
)

@Serializable
private data class TraktShowBody(
    @SerialName("title") val title: String? = null,
    @SerialName("year") val year: Int? = null,
    @SerialName("ids") val ids: TraktIdsBody? = null,
)

@Serializable
private data class TraktEpisodeBody(
    @SerialName("title") val title: String? = null,
    @SerialName("season") val season: Int? = null,
    @SerialName("number") val number: Int? = null,
)

@Serializable
private data class TraktIdsBody(
    @SerialName("trakt") val trakt: Int? = null,
    @SerialName("imdb") val imdb: String? = null,
    @SerialName("tmdb") val tmdb: Int? = null,
)
