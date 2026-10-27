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

    @Test
    fun nullPageResultFailsTheHiddenShowList() = runTest {
        // Checks only that a null page result (what the repository's loader returns for an
        // undecodable body) makes the whole collected list null. The repository's own inline
        // decode in fetchHiddenShowIds is NOT exercised: it has no seam, and an undecodable-body
        // test needs a refactor like upstream's readAllTraktPages, which the fork does not have.
        val ids = collectTraktHiddenShowIds(limit = 2) { page, _ ->
            if (page == 1) listOf(show("tt1"), show("tt2")) else null
        }
        assertNull(ids, "a null page must drop the whole list, not end it early")
    }

    @Test
    fun pageStatusErrorMessageNamesTheEndpoint() {
        // Checks requireTraktProgressPageSuccess directly (exception type and message). It does
        // not walk the history pages: the undecodable-page throw in the private
        // fetchRecentEpisodeHistoryEntries is untested for lack of a seam.
        val error = assertFailsWith<TraktProgressFetchException> {
            requireTraktProgressPageSuccess(500, url = "sync/history/episodes")
        }
        assertEquals("Trakt request sync/history/episodes failed with HTTP 500", error.message)
        assertFailsWith<TraktProgressFetchException> {
            requireTraktProgressPageSuccess(401, url = "sync/history/episodes")
        }
    }
}
