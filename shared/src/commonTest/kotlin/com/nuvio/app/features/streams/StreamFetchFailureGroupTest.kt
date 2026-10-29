package com.nuvio.app.features.streams

import com.nuvio.app.features.debrid.DebridSettings
import com.nuvio.app.features.debrid.DebridStreamPresentation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Stream picker A, P0.2: a failing add-on yields a group with [AddonStreamGroup.error] set and no
 * streams, and that state survives everything between the fan-out and the UI (presentation,
 * the empty-state reason), so a source chip can show the error state.
 */
class StreamFetchFailureGroupTest {

    @Test
    fun failedFetchYieldsAnErroredEmptyGroup() {
        val group = addonStreamGroupFromFetch(
            addonName = "Comet",
            addonId = "addon:comet",
            result = Result.failure(IllegalStateException("HTTP 502")),
        )

        assertEquals("Comet", group.addonName)
        assertEquals("addon:comet", group.addonId)
        assertEquals(emptyList(), group.streams)
        assertEquals(false, group.isLoading)
        assertEquals("HTTP 502", group.error)
    }

    @Test
    fun failureWithoutAMessageStillReadsAsAFailure() {
        // Kotlin/Native and ktor both throw exceptions whose `message` is null; before P0.2 the
        // group then carried `error = null` and the picker said "No streams found".
        val group = addonStreamGroupFromFetch(
            addonName = "Comet",
            addonId = "addon:comet",
            result = Result.failure(IllegalStateException()),
        )

        assertTrue(!group.error.isNullOrBlank(), "error should fall back to a readable message")
        assertEquals(emptyList(), group.streams)
    }

    @Test
    fun successfulFetchCarriesNoError() {
        val stream = StreamItem(name = "Comet\n2160p", url = "https://example.com/a.mkv", addonName = "Comet", addonId = "addon:comet")
        val group = addonStreamGroupFromFetch(
            addonName = "Comet",
            addonId = "addon:comet",
            result = Result.success(listOf(stream)),
        )

        assertEquals(listOf(stream), group.streams)
        assertNull(group.error)
        assertEquals(false, group.isLoading)
    }

    @Test
    fun presentationKeepsTheErrorOnAnEmptyGroup() {
        val errored = addonStreamGroupFromFetch(
            addonName = "Comet",
            addonId = "addon:comet",
            result = Result.failure(IllegalStateException("timeout")),
        )

        val badged = StreamBadgePresentation.apply(groups = listOf(errored), rules = StreamBadgeRules()).single()
        val presented = DebridStreamPresentation.apply(groups = listOf(badged), settings = DebridSettings(), allStreams = true).single()

        assertEquals("timeout", presented.error)
        assertEquals(emptyList(), presented.streams)
    }

    @Test
    fun everyAddonFailingIsAFetchFailureNotAnEmptyResult() {
        val failed = listOf(
            addonStreamGroupFromFetch("Comet", "addon:comet", Result.failure(IllegalStateException("502"))),
            addonStreamGroupFromFetch("Torrentio", "addon:torrentio", Result.failure(IllegalStateException())),
        )

        assertEquals(StreamsEmptyStateReason.StreamFetchFailed, failed.toEmptyStateReason(anyLoading = false))
        // Still loading elsewhere: no verdict yet.
        assertNull(failed.toEmptyStateReason(anyLoading = true))
    }

    @Test
    fun oneAddonFailingBesideAnEmptyOneIsNoStreamsFound() {
        val mixed = listOf(
            addonStreamGroupFromFetch("Comet", "addon:comet", Result.failure(IllegalStateException("502"))),
            addonStreamGroupFromFetch("Torrentio", "addon:torrentio", Result.success(emptyList())),
        )

        assertEquals(StreamsEmptyStateReason.NoStreamsFound, mixed.toEmptyStateReason(anyLoading = false))
    }
}
