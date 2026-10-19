package com.nuvio.app.features.trakt

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/**
 * A failed Trakt progress request must not be read as an empty result
 * (upstream NuvioTV befc72857).
 */
class TraktProgressFetchFailureTest {

    private fun show(imdb: String, tmdb: Int? = null) =
        TraktHiddenItem(show = TraktMedia(ids = TraktExternalIds(imdb = imdb, tmdb = tmdb)))

    @Test
    fun hiddenShowIdsCollectEveryPage() = runTest {
        val ids = collectTraktHiddenShowIds(limit = 2) { page, _ ->
            when (page) {
                1 -> listOf(show("tt1", tmdb = 10), show("tt2"))
                2 -> listOf(show("tt3"))
                else -> error("unexpected page $page")
            }
        }
        assertEquals(setOf("tt1", "tmdb:10", "tt2", "tt3"), ids)
    }

    @Test
    fun hiddenShowIdsFailWhenTheFirstPageFails() = runTest {
        assertNull(collectTraktHiddenShowIds(limit = 2) { _, _ -> null })
    }

    @Test
    fun hiddenShowIdsFailWhenALaterPageFails() = runTest {
        val ids = collectTraktHiddenShowIds(limit = 2) { page, _ ->
            if (page == 1) listOf(show("tt1"), show("tt2")) else null
        }
        assertNull(ids, "a partial dropped-shows set would show dropped shows again")
    }

    @Test
    fun emptyHiddenListIsASuccess() = runTest {
        assertEquals(emptySet(), collectTraktHiddenShowIds { _, _ -> emptyList() })
    }

    @Test
    fun failedHistoryPageThrowsInsteadOfEndingTheList() {
        requireTraktProgressPageSuccess(200, url = "sync/history/episodes")
        assertFailsWith<TraktProgressFetchException> {
            requireTraktProgressPageSuccess(503, url = "sync/history/episodes")
        }
        assertFailsWith<TraktProgressFetchException> {
            requireTraktProgressPageSuccess(429, url = "sync/history/episodes")
        }
    }
}
