package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.test.assertTrue

class StreamTierGroupingTest {
    @Test
    fun forResolutionFloorsToTheStep() {
        val expected = mapOf(
            2160 to StreamTier.UHD, 4320 to StreamTier.UHD, 1440 to StreamTier.QHD,
            1080 to StreamTier.FHD, 1439 to StreamTier.FHD, 720 to StreamTier.HD,
            576 to StreamTier.SD, 480 to StreamTier.SD, 360 to StreamTier.SD, 1 to StreamTier.SD,
            0 to StreamTier.OTHER, -1 to StreamTier.OTHER,
        )
        expected.forEach { (resolution, tier) -> assertEquals(tier, StreamTier.forResolution(resolution), "$resolution") }
        assertEquals(StreamTier.OTHER, StreamTier.forResolution(null))
    }

    @Test
    fun enumOrderAndLabels() {
        assertEquals(
            listOf(StreamTier.UHD, StreamTier.QHD, StreamTier.FHD, StreamTier.HD, StreamTier.SD, StreamTier.OTHER),
            StreamTier.entries,
        )
        assertEquals(listOf("4K", "1440p", "1080p", "720p", "SD", "Other"), StreamTier.entries.map { it.label })
    }

    @Test
    fun groupIndicesIsAStablePartitionBestFirst() {
        val groups = StreamTierGrouping.groupIndices(listOf(1080, 2160, 0, 720, 2160, 480))
        assertEquals(
            listOf(
                StreamTierIndices(StreamTier.UHD, listOf(1, 4)),
                StreamTierIndices(StreamTier.FHD, listOf(0)),
                StreamTierIndices(StreamTier.HD, listOf(3)),
                StreamTierIndices(StreamTier.SD, listOf(5)),
                StreamTierIndices(StreamTier.OTHER, listOf(2)),
            ),
            groups,
        )
    }

    @Test
    fun emptyInputAndNoEmptyTiers() {
        assertEquals(emptyList(), StreamTierGrouping.groupIndices(emptyList()))
        val groups = StreamTierGrouping.groupIndices(listOf(1080, 1080))
        assertEquals(1, groups.size)
        assertTrue(groups.all { it.indices.isNotEmpty() })
    }

    private fun stream(name: String) = StreamItem(name = name, url = "https://example.com/$name", addonName = "Test", addonId = "test")

    @Test
    fun groupKeepsStreamsAndFactsParallel() {
        val streams = listOf(stream("a"), stream("b"), stream("c"))
        val facts = listOf(StreamFacts(resolution = 1080), StreamFacts(resolution = 2160), StreamFacts())
        val sections = StreamTierGrouping.group(streams, facts)
        assertEquals(listOf(StreamTier.UHD, StreamTier.FHD, StreamTier.OTHER), sections.map { it.tier })
        sections.forEach { section ->
            assertEquals(section.streams.size, section.facts.size)
        }
        assertSame(streams[1], sections[0].streams.single())
        assertSame(facts[1], sections[0].facts.single())
    }

    @Test
    fun mismatchedSizesThrow() {
        assertFailsWith<IllegalArgumentException> {
            StreamTierGrouping.group(listOf(stream("a")), emptyList())
        }
    }

    @Test
    fun republishMovesTheSameInstanceBetweenTiers() {
        val item = stream("a")
        val first = StreamTierGrouping.group(listOf(item), listOf(StreamFacts(resolution = 1080)))
        val second = StreamTierGrouping.group(listOf(item), listOf(StreamFacts(resolution = 2160)))
        assertEquals(StreamTier.FHD, first.single().tier)
        assertEquals(StreamTier.UHD, second.single().tier)
        assertSame(item, first.single().streams.single())
        assertSame(item, second.single().streams.single())
    }
}
