package com.nuvio.app.features.search

import com.nuvio.app.features.addons.AddonCatalog
import com.nuvio.app.features.addons.AddonExtraProperty
import com.nuvio.app.features.addons.AddonManifest
import com.nuvio.app.features.addons.AddonResource
import com.nuvio.app.features.addons.ManagedAddon
import com.nuvio.app.features.catalog.CatalogPage
import com.nuvio.app.features.home.MetaPreview
import kotlinx.atomicfu.atomic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/// BUG-208: a search catalog whose fetch throws (Cinemeta's origin 504 on an uncached query) is
/// fetched once more; a timeout is not retried; a catalog that fails twice settles as
/// RequestFailed with an error message. The network is replaced by [SearchRepository.searchPageFetcherForTest].
class SearchCatalogRetryTest {

    @AfterTest
    fun tearDown() {
        SearchRepository.searchPageFetcherForTest = null
        SearchRepository.reset()
    }

    @Test
    fun `a failed catalog is retried once and the retry's page is shown`() = runTest {
        val calls = atomic(0)
        SearchRepository.searchPageFetcherForTest = {
            if (calls.incrementAndGet() == 1) error("HTTP 504") else page()
        }
        val state = settledSearch("avatar retry ok")
        assertEquals(2, calls.value)
        assertNull(state.emptyStateReason)
        assertNull(state.errorMessage)
        assertTrue(state.sections.isNotEmpty())
    }

    @Test
    fun `a catalog failing twice settles as RequestFailed`() = runTest {
        val calls = atomic(0)
        SearchRepository.searchPageFetcherForTest = {
            calls.incrementAndGet()
            error("HTTP 504")
        }
        val state = settledSearch("avatar retry failed")
        assertEquals(2, calls.value)
        assertEquals(SearchEmptyStateReason.RequestFailed, state.emptyStateReason)
        assertNotNull(state.errorMessage)
        assertTrue(state.sections.isEmpty())
    }

    @Test
    fun `a timeout is not retried`() = runTest {
        val calls = atomic(0)
        SearchRepository.searchPageFetcherForTest = { request ->
            calls.incrementAndGet()
            throw SearchCatalogTimeoutException(request.catalogId)
        }
        val state = settledSearch("avatar timeout")
        assertEquals(1, calls.value)
        assertEquals(SearchEmptyStateReason.RequestFailed, state.emptyStateReason)
    }

    private suspend fun settledSearch(query: String): SearchUiState {
        SearchRepository.reset()
        val id = SearchRepository.search(query = query, addons = listOf(searchableAddon()))
        return withContext(Dispatchers.Default) {
            withTimeout(5_000) {
                SearchRepository.uiState.first { it.requestId == id && !it.isLoading }
            }
        }
    }

    private fun page(): CatalogPage =
        CatalogPage(
            items = listOf(MetaPreview(id = "tt0499549", type = "movie", name = "Avatar")),
            rawItemCount = 1,
            nextSkip = null,
        )

    private fun searchableAddon(): ManagedAddon =
        ManagedAddon(
            manifestUrl = "https://retry.example/manifest.json",
            manifest = AddonManifest(
                id = "retry.example",
                name = "Retry Example",
                description = "",
                version = "1.0.0",
                resources = listOf(AddonResource(name = "meta", types = listOf("movie"))),
                types = listOf("movie"),
                catalogs = listOf(
                    AddonCatalog(
                        type = "movie",
                        id = "search",
                        name = "Search",
                        extra = listOf(AddonExtraProperty(name = "search", isRequired = true)),
                    ),
                ),
                transportUrl = "https://retry.example/manifest.json",
            ),
        )
}
