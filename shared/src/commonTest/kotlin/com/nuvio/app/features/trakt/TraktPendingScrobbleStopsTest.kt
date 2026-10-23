package com.nuvio.app.features.trakt

import com.nuvio.app.core.account.AccountDataStores
import com.nuvio.app.core.account.AppleKeySpec
import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_KEY
import com.nuvio.app.core.account.TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** BUG-220: the write-ahead Trakt `/scrobble/stop` queue and its replay. */
class TraktPendingScrobbleStopsTest {

    private class Harness(
        var nowMs: Long = 1_000_000_000L,
        var activeProfile: Int = 1,
        var connected: Boolean = true,
        val storage: MutableMap<Int, String> = mutableMapOf(),
    ) {
        private var nextId = 0
        val logs = mutableListOf<String>()

        val queue = TraktPendingScrobbleStopQueue(
            load = { storage[it] },
            save = { profileId, payload -> storage[profileId] = payload },
            clear = { storage.remove(it) },
            now = { nowMs },
        )

        /** A fresh outbox over the same storage: what the next app launch sees. */
        fun outbox() = TraktScrobbleStopOutbox(
            queue = queue,
            activeProfileId = { activeProfile },
            isConnected = { connected },
            now = { nowMs },
            newId = { "id-${nextId++}" },
            log = { logs += it },
        )

        suspend fun pending(profileId: Int = 1) = queue.pending(profileId)
    }

    private fun movie(imdb: String = "tt0111161") =
        TraktScrobbleItem.Movie(title = "Film", year = 1994, ids = TraktExternalIds(imdb = imdb))

    private fun episode(season: Int = 1, number: Int = 2) = TraktScrobbleItem.Episode(
        showTitle = "Show",
        showYear = 2020,
        showIds = TraktExternalIds(imdb = "tt0903747", tmdb = 1396),
        season = season,
        number = number,
        episodeTitle = "Pilot",
    )

    // ── Write-ahead send ──────────────────────────────────────────────────────────────────

    @Test
    fun stopIsPersistedBeforeItIsSent() = runTest {
        val h = Harness()
        var pendingDuringSend: List<TraktPendingScrobbleStop>? = null
        h.outbox().sendStop(1, movie(), 2.4f) { _, _ ->
            pendingDuringSend = h.pending()
            TraktScrobbleDelivery.SENT
        }
        val seen = pendingDuringSend!!
        assertEquals(1, seen.size)
        assertEquals(movie().itemKey, seen.single().itemKey)
        assertEquals(2.4f, seen.single().progress)
        assertEquals(1, seen.single().profileId)
        assertEquals(h.nowMs, seen.single().createdAtMs)
    }

    @Test
    fun sentStopIsDeleted() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.SENT }
        assertTrue(h.pending().isEmpty())
        assertNull(h.storage[1], "an empty queue removes the key")
    }

    @Test
    fun conflictAndDedupeDeleteTheEntry() = runTest {
        // 409 is folded into SENT by TraktScrobbleRepository.deliver (same branch as 2xx).
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.SKIPPED }
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun serverErrorKeepsTheEntryAndCountsAnAttempt() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.RETRYABLE }
        assertEquals(1, h.pending().single().attempts)
    }

    @Test
    fun offlineAndNoAuthKeepTheEntryWithoutCountingAnAttempt() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie("tt1"), 40f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.outbox().sendStop(1, movie("tt2"), 40f) { _, _ -> TraktScrobbleDelivery.NOT_READY }
        val pending = h.pending()
        assertEquals(2, pending.size)
        assertTrue(pending.all { it.attempts == 0 })
    }

    @Test
    fun rejectedStopIsDropped() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.REJECTED }
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun httpFailureClassification() {
        listOf(500, 502, 503, 504, 401, 403, 408, 420, 423, 429).forEach {
            assertEquals(TraktScrobbleDelivery.RETRYABLE, classifyTraktScrobbleFailure(it), "HTTP $it")
        }
        listOf(400, 404, 405, 422).forEach {
            assertEquals(TraktScrobbleDelivery.REJECTED, classifyTraktScrobbleFailure(it), "HTTP $it")
        }
    }

    @Test
    fun noConnectedAccountOrBelowOnePercentIsSentButNeverQueued() = runTest {
        val h = Harness(connected = false)
        var sends = 0
        h.outbox().sendStop(1, movie("tt1"), 40f) { _, _ -> sends++; TraktScrobbleDelivery.NOT_READY }
        h.connected = true
        h.outbox().sendStop(1, movie("tt2"), 0.5f) { _, _ -> sends++; TraktScrobbleDelivery.OFFLINE }
        assertEquals(2, sends)
        assertTrue(h.pending().isEmpty())
    }

    // ── Replay ────────────────────────────────────────────────────────────────────────────

    @Test
    fun drainAtLaunchReplaysWhatTheLastRunLeftBehind() = runTest {
        val h = Harness()
        // Run 1: the app is killed before the request lands (OFFLINE stands in for "never answered").
        h.outbox().sendStop(1, episode(), 2.4f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        assertEquals(1, h.pending().size)

        // Run 2: a fresh outbox over the same storage drains at profile selection.
        val replayed = mutableListOf<Pair<TraktScrobbleItem, Float>>()
        val result = h.outbox().drain(1) { item, progress ->
            replayed += item to progress
            TraktScrobbleDelivery.SENT
        }
        assertEquals(listOf<Pair<TraktScrobbleItem, Float>>(episode() to 2.4f), replayed)
        assertEquals(TraktPendingStopDrainResult(sent = 1, kept = 0, dropped = 0), result)
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun drainStopsAtTheFirstOfflineEntryAndKeepsTheRest() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie("tt1"), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.nowMs += 1
        h.outbox().sendStop(1, movie("tt2"), 20f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        var calls = 0
        val result = h.outbox().drain(1) { _, _ -> calls++; TraktScrobbleDelivery.OFFLINE }
        assertEquals(1, calls, "offline: no point sending the rest")
        assertEquals(2, result.kept)
        assertTrue(h.pending().all { it.attempts == 0 })
    }

    @Test
    fun drainDropsAnEntryAfterTheMaximumHttpFailures() = runTest {
        val h = Harness()
        val outbox = h.outbox()
        outbox.sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.RETRYABLE } // attempt 1
        repeat(outbox.maxReplayAttempts - 2) {
            outbox.drain(1) { _, _ -> TraktScrobbleDelivery.RETRYABLE }
        }
        assertEquals(outbox.maxReplayAttempts - 1, h.pending().single().attempts)
        val last = outbox.drain(1) { _, _ -> TraktScrobbleDelivery.RETRYABLE }
        assertEquals(1, last.dropped)
        assertTrue(h.pending().isEmpty())
    }

    @Test
    fun drainLeavesTheItemOfTheOpenSessionAlone() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        val outbox = h.outbox()
        outbox.onSessionStarted(1, movie().itemKey)
        var calls = 0
        outbox.drain(1) { _, _ -> calls++; TraktScrobbleDelivery.SENT }
        assertEquals(0, calls, "a replay must not end the session that is playing")
        assertEquals(1, h.pending().size)
    }

    @Test
    fun newerStopSupersedesTheOlderEntryForTheSameItem() = runTest {
        val h = Harness()
        val outbox = h.outbox()
        outbox.sendStop(1, movie(), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.nowMs += 60_000
        outbox.sendStop(1, movie(), 35f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        assertEquals(listOf(35f), h.pending().map { it.progress })
    }

    @Test
    fun drainSkipsAnEntrySupersededWhileItRan() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie("tt1"), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.nowMs += 1
        h.outbox().sendStop(1, movie("tt2"), 20f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        val outbox = h.outbox()
        val sent = mutableListOf<String>()
        outbox.drain(1) { item, _ ->
            sent += item.itemKey
            // While the first replay is in flight, a live stop for tt2 supersedes its old entry.
            if (item.itemKey == movie("tt1").itemKey) {
                h.queue.enqueue(
                    TraktPendingScrobbleStop(
                        id = "live",
                        profileId = 1,
                        itemKey = movie("tt2").itemKey,
                        item = TraktPendingScrobbleItem.from(movie("tt2")),
                        progress = 50f,
                        createdAtMs = h.nowMs + 1,
                    ),
                )
            }
            TraktScrobbleDelivery.SENT
        }
        assertEquals(listOf(movie("tt1").itemKey), sent, "the stale 20 % stop must not be replayed")
        assertEquals(listOf("live"), h.pending().map { it.id })
    }

    // ── Bounds ────────────────────────────────────────────────────────────────────────────

    @Test
    fun queueKeepsOnlyTheNewestEntriesPerProfile() = runTest {
        val h = Harness()
        val outbox = h.outbox()
        val total = h.queue.maxPerProfile + 3
        for (index in 0 until total) {
            h.nowMs += 1
            outbox.sendStop(1, movie("tt$index"), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        }
        val pending = h.pending()
        assertEquals(h.queue.maxPerProfile, pending.size)
        assertEquals(movie("tt3").itemKey, pending.first().itemKey, "the oldest three were dropped")
        assertEquals(movie("tt${total - 1}").itemKey, pending.last().itemKey)
    }

    @Test
    fun entriesOlderThanSevenDaysAreNeverReplayed() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 40f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.nowMs += h.queue.maxAgeMs + 1
        var calls = 0
        h.outbox().drain(1) { _, _ -> calls++; TraktScrobbleDelivery.SENT }
        assertEquals(0, calls)
        assertNull(h.storage[1], "the expired entry is pruned from storage")
    }

    @Test
    fun undecodablePayloadIsDiscarded() = runTest {
        val h = Harness()
        h.storage[1] = "{not json"
        assertTrue(h.pending().isEmpty())
        assertNull(h.storage[1])
    }

    // ── Profile scoping ───────────────────────────────────────────────────────────────────

    @Test
    fun stopsAreKeptUnderTheProfileThatPlayedThem() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie("tt1"), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.activeProfile = 2
        h.outbox().sendStop(2, movie("tt2"), 20f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        assertEquals(listOf(movie("tt1").itemKey), h.pending(1).map { it.itemKey })
        assertEquals(listOf(movie("tt2").itemKey), h.pending(2).map { it.itemKey })
    }

    @Test
    fun drainOnlyRunsForTheActiveProfile() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.activeProfile = 2
        var calls = 0
        h.outbox().drain(1) { _, _ -> calls++; TraktScrobbleDelivery.SENT }
        h.outbox().drain(2) { _, _ -> calls++; TraktScrobbleDelivery.SENT }
        assertEquals(0, calls)
        assertEquals(1, h.pending(1).size)
    }

    @Test
    fun drainStopsWhenTheProfileChangesMidway() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie("tt1"), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.nowMs += 1
        h.outbox().sendStop(1, movie("tt2"), 20f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        var calls = 0
        h.outbox().drain(1) { _, _ ->
            calls++
            h.activeProfile = 2
            TraktScrobbleDelivery.SENT
        }
        assertEquals(1, calls)
        assertEquals(listOf(movie("tt2").itemKey), h.pending(1).map { it.itemKey })
    }

    // ── Sign-out wipe / disconnect ────────────────────────────────────────────────────────

    @Test
    fun accountWipeRegistryListsThePendingStopStore() {
        val store = AccountDataStores.all.single { it.name == "TraktPendingScrobbleStopStorage" }
        assertEquals(TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES, store.androidPreferences)
        assertTrue(AppleKeySpec.ProfileScoped(TRAKT_PENDING_SCROBBLE_STOPS_KEY) in store.appleKeys)
        assertTrue(TRAKT_PENDING_SCROBBLE_STOPS_KEY in AccountDataStores.appleProfileScopedBases())
        assertTrue(TRAKT_PENDING_SCROBBLE_STOPS_PREFERENCES in AccountDataStores.androidPreferenceNames())
    }

    @Test
    fun wipedStorageIsNotWrittenBackByAnInFlightDrain() = runTest {
        val h = Harness()
        h.outbox().sendStop(1, movie(), 10f) { _, _ -> TraktScrobbleDelivery.OFFLINE }
        h.outbox().drain(1) { _, _ ->
            h.storage.clear() // the sign-out wipe lands while the replay is in flight
            TraktScrobbleDelivery.RETRYABLE
        }
        assertTrue(h.storage.isEmpty(), "recording the failed attempt must not resurrect the entry")
    }

    @Test
    fun platformStorageIsAddressedPerProfileAndClears() {
        val profileA = 7
        val profileB = 8
        try {
            TraktPendingScrobbleStopStorage.save(profileA, "a")
            TraktPendingScrobbleStopStorage.save(profileB, "b")
            assertEquals("a", TraktPendingScrobbleStopStorage.load(profileA))
            assertEquals("b", TraktPendingScrobbleStopStorage.load(profileB))
            TraktPendingScrobbleStopStorage.clear(profileA)
            assertNull(TraktPendingScrobbleStopStorage.load(profileA))
            assertEquals("b", TraktPendingScrobbleStopStorage.load(profileB))
        } finally {
            TraktPendingScrobbleStopStorage.clear(profileA)
            TraktPendingScrobbleStopStorage.clear(profileB)
        }
    }

    @Test
    fun itemSnapshotRoundTripsBothKinds() {
        assertEquals(movie(), TraktPendingScrobbleItem.from(movie()).toScrobbleItem())
        assertEquals(episode(3, 4), TraktPendingScrobbleItem.from(episode(3, 4)).toScrobbleItem())
        assertNull(TraktPendingScrobbleItem(kind = "movie").toScrobbleItem(), "no ids, never replayed")
    }
}
