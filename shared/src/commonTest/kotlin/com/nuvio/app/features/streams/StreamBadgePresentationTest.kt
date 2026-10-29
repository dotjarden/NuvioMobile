package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals

class StreamBadgePresentationTest {
    @Test
    fun `applies new rules after reusing the previous ones`() {
        fun rules(name: String, pattern: String) = StreamBadgeRules(
            imports = listOf(
                StreamBadgeImport(
                    sourceUrl = "https://example.test/badges.json",
                    filters = listOf(
                        StreamBadgeFilter(name = name, pattern = pattern, imageURL = "https://example.test/$name.png"),
                    ),
                ),
            ),
        )
        val group = AddonStreamGroup(
            addonName = "Direct",
            addonId = "direct",
            streams = listOf(
                StreamItem(
                    name = "Movie.2026.2160p.WEB-DL.REMUX-GRP",
                    url = "https://example.test/movie.mp4",
                    addonName = "Direct",
                    addonId = "direct",
                ),
            ),
        )
        fun badgeNames(rules: StreamBadgeRules) =
            StreamBadgePresentation.apply(listOf(group), rules).single().streams.single().badges.map { it.name }

        val webRules = rules("WEB", "(?i)web-dl")
        assertEquals(listOf("WEB"), badgeNames(webRules))
        assertEquals(listOf("WEB"), badgeNames(webRules))
        assertEquals(listOf("WEB"), badgeNames(rules("WEB", "(?i)web-dl")))
        assertEquals(listOf("REMUX"), badgeNames(rules("REMUX", "(?i)remux")))
        assertEquals(emptyList(), badgeNames(StreamBadgeRules()))
        assertEquals(listOf("WEB"), badgeNames(webRules))
    }
}
