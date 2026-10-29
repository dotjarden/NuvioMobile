package com.nuvio.app.features.streams

/**
 * Quality tiers for the stream list (polish batch D4), best first. Direction C's collapsible
 * tier sections reuse this enum and [StreamTierGrouping]. Thresholds floor to the step: a stream
 * is never shown in a tier above its resolution.
 */
enum class StreamTier(val label: String) {
    UHD("4K"), // >= 2160
    QHD("1440p"), // 1440 ..< 2160
    FHD("1080p"), // 1080 ..< 1440
    HD("720p"), // 720 ..< 1080
    SD("SD"), // 1 ..< 720
    OTHER("Other"); // resolution unknown (null or <= 0)

    companion object {
        fun forResolution(resolution: Int?): StreamTier = when {
            resolution == null || resolution <= 0 -> OTHER
            resolution >= 2160 -> UHD
            resolution >= 1440 -> QHD
            resolution >= 1080 -> FHD
            resolution >= 720 -> HD
            else -> SD
        }
    }
}

/** One tier's streams, in input order, with their facts (parallel lists). */
data class StreamTierSection(
    val tier: StreamTier,
    val streams: List<StreamItem>,
    val facts: List<StreamFacts>,
)

/** One tier's positions in the input list, ascending. Swift's entry point. */
data class StreamTierIndices(
    val tier: StreamTier,
    val indices: List<Int>,
)

object StreamTierGrouping {
    /**
     * Stable partition by tier: tiers in [StreamTier] order, input order kept inside each tier,
     * empty tiers dropped, no re-sort. `resolutions[i]` <= 0 means unknown (Swift passes 0 for
     * nil: a `List<Int?>` does not bridge).
     */
    fun groupIndices(resolutions: List<Int>): List<StreamTierIndices> {
        val byTier = StreamTier.entries.associateWith { mutableListOf<Int>() }
        resolutions.forEachIndexed { index, resolution ->
            byTier.getValue(StreamTier.forResolution(resolution)).add(index)
        }
        return StreamTier.entries.mapNotNull { tier ->
            byTier.getValue(tier).takeIf { it.isNotEmpty() }?.let { StreamTierIndices(tier, it.toList()) }
        }
    }

    /** The same partition over streams with their parsed facts (`streams.size == facts.size`). */
    fun group(streams: List<StreamItem>, facts: List<StreamFacts>): List<StreamTierSection> {
        require(streams.size == facts.size) {
            "streams (${streams.size}) and facts (${facts.size}) must be parallel"
        }
        return groupIndices(facts.map { it.resolution ?: 0 }).map { section ->
            StreamTierSection(
                tier = section.tier,
                streams = section.indices.map { streams[it] },
                facts = section.indices.map { facts[it] },
            )
        }
    }
}
