package com.nuvio.app.features.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** FEAT-73 (Steven rc4): the catalog the grid-first Discover page opens on. */
class DiscoverGridDefaultCatalogTest {
    private val plain = option("a:movie:plain", genres = emptyList(), required = false)
    private val required = option("a:movie:req", genres = listOf("Action", "Drama"), required = true)
    private val optional = option("a:movie:opt", genres = listOf("Comedy"), required = false)
    private val series = option("a:series:top", genres = listOf("Drama"), required = false)

    @Test
    fun persistedPickWinsWhenOfferedForTheType() {
        val options = listOf(plain, required, optional, series)
        assertEquals(required, DiscoverSources.gridDefaultCatalog(options, "movie", " a:movie:req "))
    }

    @Test
    fun persistedPickOfAnotherTypeIsIgnored() {
        val options = listOf(plain, required, optional, series)
        assertEquals(optional, DiscoverSources.gridDefaultCatalog(options, "movie", "a:series:top"))
    }

    @Test
    fun unknownPersistedPickFallsBackToTheRule() {
        val options = listOf(plain, required, optional)
        assertEquals(optional, DiscoverSources.gridDefaultCatalog(options, "movie", "gone"))
    }

    @Test
    fun prefersOptionalGenreThenRequiredGenreThenFirst() {
        assertEquals(optional, DiscoverSources.gridDefaultCatalog(listOf(plain, required, optional), "movie", null))
        assertEquals(required, DiscoverSources.gridDefaultCatalog(listOf(plain, required), "movie", null))
        assertEquals(plain, DiscoverSources.gridDefaultCatalog(listOf(plain), "movie", null))
    }

    @Test
    fun nullTypeUsesTheFirstOptionsType() {
        assertEquals(series, DiscoverSources.gridDefaultCatalog(listOf(series, optional), null, null))
    }

    /// Review r1 (P2): on a cold start (no type) a persisted Series pick wins over the first type.
    @Test
    fun nullTypeHonoursAPersistedPickOfAnotherType() {
        assertEquals(series, DiscoverSources.gridDefaultCatalog(listOf(optional, series), null, series.key))
    }

    @Test
    fun noOptionsOfTheTypeIsNull() {
        assertNull(DiscoverSources.gridDefaultCatalog(listOf(series), "movie", null))
        assertNull(DiscoverSources.gridDefaultCatalog(emptyList(), null, null))
    }

    private fun option(key: String, genres: List<String>, required: Boolean) = DiscoverCatalogOption(
        key = key,
        addonName = "Addon",
        manifestUrl = "https://example.com/manifest.json",
        type = key.split(":")[1],
        catalogId = key,
        catalogName = key,
        genreOptions = genres,
        genreRequired = required,
    )
}
