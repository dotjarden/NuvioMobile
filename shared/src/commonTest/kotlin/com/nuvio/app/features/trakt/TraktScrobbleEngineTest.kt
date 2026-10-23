package com.nuvio.app.features.trakt

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Instant

/** BUG-220 review round 1: the repository's request path, replay and triggers (via [TraktScrobbleEngine]). */
class TraktScrobbleEngineTest {

    private data class Call(val method: String, val url: String, val body: String)

    private class Harness(scope: CoroutineScope) {
        var nowMs = 1_800_000_000_000L
        var activeProfile = 1
        val auth = MutableStateFlow(true)
        var slug: String? = null
        val storage = mutableMapOf<Int, String>()
        val calls = mutableListOf<Call>()
        val sleeps = mutableListOf<Long>()
        var refreshes = 0
        private var nextId = 0

        /** POST /scrobble replies, consumed in order; the last one repeats. null = transport failure. */
        var postReplies: MutableList<TraktHttpReply?> = mutableListOf(TraktHttpReply(201))
        var playbackJson = "[]"
        var historyJson = "[]"
        var onPost: (suspend () -> Unit)? = null
        var throwOnNextCall = false

        val queue = TraktPendingScrobbleStopQueue(
            load = { storage[it] },
            save = { profileId, payload -> storage[profileId] = payload },
            clear = { storage.remove(it) },
            now = { nowMs },
        )

        val engine = TraktScrobbleEngine(
            activeProfileId = { activeProfile },
            authorizedHeaders = { if (auth.value) mapOf("Authorization" to "Bearer abcdefghijkl") else null },
            isAuthenticated = { auth.value },
            authenticatedChanges = { auth },
            accountSlug = { slug },
            refreshAccount = {},
            http = { method, url, body, _ ->
                if (throwOnNextCall) {
                    throwOnNextCall = false
                    throw IllegalStateException("boom")
                }
                calls += Call(method, url, body)
                when {
                    method == "POST" -> {
                        onPost?.let { hook -> onPost = null; hook() }
                        if (postReplies.size > 1) postReplies.removeAt(0) else postReplies.firstOrNull()
                    }
                    "/sync/playback/" in url -> TraktHttpReply(200, body = playbackJson)
                    "/sync/history/" in url -> TraktHttpReply(200, body = historyJson)
                    else -> TraktHttpReply(404)
                }
            },
            refreshProgress = { refreshes += 1 },
            queue = queue,
            now = { nowMs },
            newId = { "id-${nextId++}" },
            scope = scope,
            appVersion = "test",
            parseIsoMs = ::parseTraktIsoDateTimeToEpochMs,
            formatIsoMs = { ms -> Instant.fromEpochMilliseconds(ms).toString() },
            sleep = { sleeps += it },
        )

        val posts get() = calls.filter { it.method == "POST" }
        suspend fun pending() = queue.pending(1)
    }

    private fun TestScope.harness() = Harness(backgroundScope)

    private val film = TraktScrobbleItem.Movie(title = "Film", year = 1994, ids = TraktExternalIds(imdb = "tt0111161"))

    /** Leaves a stop behind as a killed app would: one transport failure on every attempt. */
    private suspend fun Harness.leaveStopBehind(progress: Float = 40f) {
        postReplies = mutableListOf(null)
        engine.send(1, "stop", film, progress)
        postReplies = mutableListOf(TraktHttpReply(201))
        calls.clear()
        sleeps.clear()
    }

    // ── Status → delivery mapping ─────────────────────────────────────────────────────────

    @Test
    fun conflictIsSentAndTransportFailuresToTheEndAreOffline() = runTest {
        val sleeps = mutableListOf<Long>()
        suspend fun run(attempts: Int, vararg replies: TraktHttpReply?): Pair<TraktScrobbleDelivery, Int> {
            var sent = 0
            val queued = replies.toMutableList()
            val result = runTraktScrobbleAttempts(attempts, 1_500, 5_000, { sleeps += it }) {
                sent += 1
                if (queued.size > 1) queued.removeAt(0) else queued.first()
            }
            return result to sent
        }
        assertEquals(TraktScrobbleDelivery.SENT to 1, run(3, TraktHttpReply(409)))
        assertEquals(TraktScrobbleDelivery.OFFLINE to 3, run(3, null))
        assertEquals(listOf(1_500L, 3_000L), sleeps)
        assertEquals(TraktScrobbleDelivery.SENT to 2, run(3, TraktHttpReply(503), TraktHttpReply(201)))
        assertEquals(5_000L, sleeps.last())
        assertEquals(TraktScrobbleDelivery.RETRYABLE to 3, run(3, TraktHttpReply(500)))
        assertEquals(TraktScrobbleDelivery.REJECTED to 1, run(3, TraktHttpReply(422)))
        assertEquals(TraktScrobbleDelivery.OFFLINE to 1, run(1, null))
    }

    @Test
    fun liveStopIsQueuedThenRemovedAndRefreshes() = runTest {
        val h = harness()
        h.engine.send(1, "stop", film, 40f)
        assertEquals(1, h.posts.size)
        assertTrue(h.pending().isEmpty())
        assertEquals(1, h.refreshes)
    }

    @Test
    fun liveStopRetriesInPlaceAndStaysQueuedWhenItNeverLands() = runTest {
        val h = harness()
        h.postReplies = mutableListOf(null)
        h.engine.send(1, "stop", film, 40f)
        assertEquals(3, h.posts.size)
        assertEquals(1, h.pending().size)
        assertEquals(0, h.refreshes)
    }

    // ── Replay ────────────────────────────────────────────────────────────────────────────

    @Test
    fun replaySendsOnceAndRefreshesOnlyWhenSomethingWasSent() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.postReplies = mutableListOf(null)
        h.engine.replay(1)
        assertEquals(1, h.posts.size, "a replay never retries in place")
        assertTrue(h.sleeps.isEmpty())
        assertEquals(0, h.refreshes)
        assertEquals(1, h.pending().size)

        h.postReplies = mutableListOf(TraktHttpReply(422))
        h.engine.replay(1)
        assertEquals(0, h.refreshes, "a rejected replay sends nothing to refresh")
        assertTrue(h.pending().isEmpty())

        h.leaveStopBehind()
        h.engine.replay(1)
        assertEquals(1, h.refreshes)
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun replayIgnoresTheLiveDedupe() = runTest {
        val h = harness()
        h.engine.send(1, "stop", film, 40f) // delivered: the 8 s dedupe stamp now covers film at 40 %
        h.calls.clear()
        h.queue.enqueue(
            TraktPendingScrobbleStop(
                id = "left",
                profileId = 1,
                itemKey = film.itemKey,
                item = TraktPendingScrobbleItem.from(film),
                progress = 40f,
                createdAtMs = h.nowMs,
            ),
        )
        h.engine.replay(1)
        assertEquals(1, h.posts.size, "a replay is never deduped away")
    }

    @Test
    fun replayChecksTraktHistoryBeforeAWatchedStop() = runTest {
        val h = harness()
        h.leaveStopBehind(progress = 95f)
        val landedAt = Instant.fromEpochMilliseconds(h.nowMs + 3_000).toString()
        h.historyJson = """[{"watched_at":"$landedAt","movie":{"ids":{"imdb":"tt0111161","trakt":1}}}]"""
        h.nowMs += 60 * 60 * 1000
        val result = h.engine.replay(1)
        assertEquals(0, h.posts.size)
        assertEquals(1, result.superseded)
        assertTrue(h.pending().isEmpty())
        val historyCall = h.calls.single { it.method == "GET" }
        assertTrue("/sync/history/movies?start_at=" in historyCall.url, historyCall.url)
    }

    @Test
    fun replayChecksTraktPlaybackBeforeAPausedStop() = runTest {
        val h = harness()
        h.leaveStopBehind(progress = 30f)
        val newer = Instant.fromEpochMilliseconds(h.nowMs + 600_000).toString()
        h.playbackJson = """[{"paused_at":"$newer","progress":55.0,"movie":{"ids":{"imdb":"tt0111161"}}}]"""
        h.engine.replay(1)
        assertEquals(0, h.posts.size, "newer progress from another device wins")
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun aLiveStopRacingADrainIsSentOnce() = runTest {
        val h = harness()
        h.postReplies = mutableListOf(null, TraktHttpReply(201))
        // While the live stop waits between attempts, a drain runs (auth watcher, profile selection).
        h.onPost = { h.engine.replay(1) }
        h.engine.send(1, "stop", film, 40f)
        assertEquals(2, h.posts.size, "attempt 1 and its retry, no replay of the in-flight entry")
        assertTrue(h.pending().isEmpty())
    }

    // ── Triggers ──────────────────────────────────────────────────────────────────────────

    @Test
    fun authWatcherReplaysWhenTraktAuthTurnsOn() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.auth.value = false
        h.engine.onProfileChanged(1)
        runCurrent()
        assertEquals(0, h.posts.size, "no auth yet: nothing sent")
        assertEquals(1, h.pending().size)

        h.auth.value = true
        runCurrent()
        assertEquals(1, h.posts.size)
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun firstProfileSelectionWithAuthReplaysOnceAndLaterSelectionsReplayAgain() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.engine.onProfileChanged(1)
        runCurrent()
        assertEquals(1, h.posts.size, "the watcher's first emission covers the first selection")

        h.nowMs += 60_000 // past the live 8 s dedupe window, or the second stop is SKIPPED (already sent)
        h.leaveStopBehind()
        h.engine.onProfileChanged(1) // auth stays true: the explicit request drains
        runCurrent()
        assertEquals(1, h.posts.size)
        assertTrue(h.pending().isEmpty())
    }

    // ── Clearing ──────────────────────────────────────────────────────────────────────────

    @Test
    fun disconnectClearIsNotWrittenBackByAnInFlightReplay() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.postReplies = mutableListOf(TraktHttpReply(500))
        h.onPost = { h.engine.clearPendingStops(1) } // disconnect lands while the replay is in flight
        h.engine.replay(1)
        assertNull(h.storage[1])
    }

    @Test
    fun signOutWipeClearsEveryProfileSlot() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.activeProfile = 3
        h.postReplies = mutableListOf(null)
        h.engine.send(3, "stop", film.copy(ids = TraktExternalIds(imdb = "tt2")), 30f)
        h.engine.onAccountDataWiped(1..6)
        runCurrent()
        assertTrue(h.storage.isEmpty())
    }

    @Test
    fun removalClearRunsUnderTheLock() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.engine.clearPendingStopsAsync(1)
        runCurrent()
        assertNull(h.storage[1])
    }

    // ── Review round 2 (P3-d, re-run after a busy drain) ──────────────────────────────────

    @Test
    fun theReplayWorkerSurvivesAThrownReplay() = runTest {
        val h = harness()
        h.leaveStopBehind()
        h.throwOnNextCall = true
        h.engine.requestReplay(1)
        runCurrent()
        assertEquals(0, h.posts.size)
        assertEquals(1, h.pending().size, "the failed drain keeps the entry")

        h.engine.requestReplay(1)
        runCurrent()
        assertEquals(1, h.posts.size, "the worker is still alive")
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun aRequestDuringABusyDrainRunsAnotherDrain() = runTest {
        val h = harness()
        h.leaveStopBehind()
        val other = TraktScrobbleItem.Movie(title = "Other", year = 2001, ids = TraktExternalIds(imdb = "tt2"))
        h.onPost = {
            // While the worker's drain is sending, another stop is left behind and a drain requested.
            h.queue.enqueue(
                TraktPendingScrobbleStop(
                    id = "late",
                    profileId = 1,
                    itemKey = other.itemKey,
                    item = TraktPendingScrobbleItem.from(other),
                    progress = 30f,
                    createdAtMs = h.nowMs,
                ),
            )
            h.engine.requestReplay(1)
        }
        h.engine.requestReplay(1)
        runCurrent()
        assertEquals(2, h.posts.size, "the second request is not lost while the first drain runs")
        assertTrue(h.pending().isEmpty())
    }
}
