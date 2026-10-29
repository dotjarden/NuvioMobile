package com.nuvio.app.features.plugins

import kotlin.test.Test
import kotlin.test.assertEquals

/** Upstream NuvioTV 8b60bdfe1. */
class PluginMediaTypeTest {
    @Test
    fun episodicTvUsesDeclaredSeriesType() {
        assertEquals("series", jsPluginMediaType("tv", listOf("movie", "series"), 1, 1))
        assertEquals("series", jsPluginMediaType("TV", listOf("SERIES", "tv"), 0, 1))
    }

    @Test
    fun legacyTvOnlyPluginsRetainTv() {
        assertEquals("tv", jsPluginMediaType("tv", listOf("movie", "tv"), 1, 1))
        assertEquals("tv", jsPluginMediaType("tv", emptyList(), 1, 1))
    }

    @Test
    fun tvWithoutSeasonAndEpisodeRemainsTv() {
        assertEquals("tv", jsPluginMediaType("tv", listOf("series", "tv"), null, null))
        assertEquals("tv", jsPluginMediaType("tv", listOf("series"), 1, null))
        assertEquals("tv", jsPluginMediaType("tv", listOf("series"), null, 1))
    }

    @Test
    fun otherRequestTypesRemainUnchanged() {
        for (type in listOf("movie", "series", "anime", "channel", "custom")) {
            assertEquals(type, jsPluginMediaType(type, listOf("series", type), 1, 1))
            assertEquals(type, jsPluginMediaType(type, listOf("series", type), null, null))
        }
    }

    @Test
    fun normalizedSeriesRequestFromTheForkIsRestored() {
        assertEquals("series", jsPluginMediaType(normalizePluginType("series"), listOf("series"), 2, 3))
    }
}
