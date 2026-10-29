package com.nuvio.app.features.catalog

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * BUG-155 (Steven, beta.19-rc3 follow-ups 2026-10-14): the waiter count behind
 * `deduplicatedHttpGetText`. A shared catalog fetch is cancelled only when its LAST waiter leaves,
 * so a superseded search stops its HTTP request while Home or Discover waiting on the same URL keep
 * theirs, and a caller arriving after the cancel starts a fresh fetch.
 */
class CatalogInflightRequestsTest {

    /** A fetch that parks on a gate per start and records starts and cancellations. */
    private class FakeFetch {
        val gates = mutableListOf<CompletableDeferred<String>>()
        var cancellations = 0

        suspend fun fetch(@Suppress("UNUSED_PARAMETER") key: String): String {
            val gate = CompletableDeferred<String>()
            gates += gate
            try {
                return gate.await()
            } catch (error: CancellationException) {
                cancellations += 1
                throw error
            }
        }
    }

    private fun TestScope.registry(
        fake: FakeFetch,
        cancelAbandoned: Boolean = true,
    ): Pair<CatalogInflightRequests<String>, CoroutineScope> {
        val fetchScope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        return CatalogInflightRequests<String>(
            scope = fetchScope,
            fetch = fake::fetch,
            cancelAbandoned = { cancelAbandoned },
        ) to fetchScope
    }

    @Test
    fun oneOfTwoWaitersCancelling_keepsTheSharedFetch() = runTest {
        val fake = FakeFetch()
        val (requests, fetchScope) = registry(fake)
        val search = async { requests.get("url") }
        val home = async { requests.get("url") }
        advanceUntilIdle()
        assertEquals(1, fake.gates.size, "two waiters on one URL share one fetch")
        assertEquals(1, requests.inflightCount)

        search.cancel()
        advanceUntilIdle()
        assertEquals(0, fake.cancellations, "Home still waits, so the fetch must keep running")
        assertEquals(0, requests.cancelledCount)
        assertEquals(1, requests.inflightCount)

        fake.gates.single().complete("payload")
        assertEquals("payload", home.await())
        advanceUntilIdle()
        assertEquals(0, requests.inflightCount)
        fetchScope.cancel()
    }

    @Test
    fun lastWaiterCancelling_cancelsTheFetch() = runTest {
        val fake = FakeFetch()
        val (requests, fetchScope) = registry(fake)
        val first = async { requests.get("url") }
        val second = async { requests.get("url") }
        advanceUntilIdle()

        first.cancel()
        second.cancel()
        advanceUntilIdle()
        assertEquals(1, fake.cancellations, "the fetch must be cancelled once nobody waits")
        assertEquals(1, requests.cancelledCount)
        assertEquals(0, requests.inflightCount)
        fetchScope.cancel()
    }

    @Test
    fun lateJoinerAfterTheCancel_getsAFreshFetch() = runTest {
        val fake = FakeFetch()
        val (requests, fetchScope) = registry(fake)
        val abandoned = async { requests.get("url") }
        advanceUntilIdle()
        abandoned.cancel()
        advanceUntilIdle()
        assertEquals(1, fake.cancellations)

        val late = async { requests.get("url") }
        advanceUntilIdle()
        assertEquals(2, fake.gates.size, "a caller after the cancel must start a new fetch")
        assertTrue(fake.gates[0].isActive, "the first gate was never completed, only its fetch cancelled")
        fake.gates[1].complete("fresh")
        assertEquals("fresh", late.await())
        fetchScope.cancel()
    }

    @Test
    fun completedFetch_isNotCountedAsCancelled() = runTest {
        val fake = FakeFetch()
        val (requests, fetchScope) = registry(fake)
        val waiter = async { requests.get("url") }
        advanceUntilIdle()
        fake.gates.single().complete("done")
        assertEquals("done", waiter.await())
        advanceUntilIdle()
        assertEquals(0, requests.cancelledCount)
        assertEquals(0, fake.cancellations)
        assertEquals(0, requests.inflightCount)
        fetchScope.cancel()
    }

    @Test
    fun legacyMode_leavesTheAbandonedFetchRunning() = runTest {
        val fake = FakeFetch()
        val (requests, fetchScope) = registry(fake, cancelAbandoned = false)
        val abandoned = async { requests.get("url") }
        advanceUntilIdle()
        abandoned.cancel()
        advanceUntilIdle()
        assertEquals(0, fake.cancellations, "-debug.searchLegacy: the pre-fix fetch runs on")
        assertEquals(0, requests.cancelledCount)
        assertEquals(1, requests.inflightCount)
        assertFalse(fake.gates.single().isCompleted)

        // A joiner reuses the still-running fetch, as before the fix.
        val joiner = async { requests.get("url") }
        advanceUntilIdle()
        assertEquals(1, fake.gates.size)
        fake.gates.single().complete("late")
        assertEquals("late", joiner.await())
        fetchScope.cancel()
    }
}
