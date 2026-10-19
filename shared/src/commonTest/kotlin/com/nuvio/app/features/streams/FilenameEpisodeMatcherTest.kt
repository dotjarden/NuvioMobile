package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * The first block is upstream NuvioTV's `FilenameEpisodeMatcherTest` (added in 7938aa3d3 for
 * 953938c72 / 829f0bbd9), renamed to camelCase (Kotlin/Native rejects some characters in
 * backtick test names) and moved from JUnit to kotlin.test. The rest covers the fork's
 * `expectedNextFilename` / `findMatch`.
 */
class FilenameEpisodeMatcherTest {

    // --- buildNextFilename (upstream) ---

    @Test
    fun sxxexxPatternReplacesEpisodeNumber() {
        assertEquals(
            "Show.Name.S01E04.1080p.WEB-DL.mkv",
            FilenameEpisodeMatcher.buildNextFilename("Show.Name.S01E03.1080p.WEB-DL.mkv", 1, 3, 1, 4),
        )
    }

    @Test
    fun sxxexxPatternReplacesSeasonAndEpisode() {
        assertEquals(
            "Show.Name.S02E01.1080p.mkv",
            FilenameEpisodeMatcher.buildNextFilename("Show.Name.S01E12.1080p.mkv", 1, 12, 2, 1),
        )
    }

    @Test
    fun sxExWithoutZeroPadding() {
        assertEquals("Show.S1E4.mkv", FilenameEpisodeMatcher.buildNextFilename("Show.S1E3.mkv", 1, 3, 1, 4))
    }

    @Test
    fun lowercaseSxxexx() {
        assertEquals(
            "show.s01e04.web.mkv",
            FilenameEpisodeMatcher.buildNextFilename("show.s01e03.web.mkv", 1, 3, 1, 4),
        )
    }

    @Test
    fun oneX03Pattern() {
        assertEquals("Show.1x04.DVDRip.mkv", FilenameEpisodeMatcher.buildNextFilename("Show.1x03.DVDRip.mkv", 1, 3, 1, 4))
    }

    @Test
    fun zeroOneX03PatternWithZeroPadding() {
        assertEquals("Show.01x04.DVDRip.mkv", FilenameEpisodeMatcher.buildNextFilename("Show.01x03.DVDRip.mkv", 1, 3, 1, 4))
    }

    @Test
    fun ep03Pattern() {
        assertEquals("Anime.EP04.720p.mkv", FilenameEpisodeMatcher.buildNextFilename("Anime.EP03.720p.mkv", null, 3, null, 4))
    }

    @Test
    fun epDot03Pattern() {
        assertEquals("Anime.EP.04.720p.mkv", FilenameEpisodeMatcher.buildNextFilename("Anime.EP.03.720p.mkv", null, 3, null, 4))
    }

    @Test
    fun e03Pattern() {
        assertEquals("Show.E04.mkv", FilenameEpisodeMatcher.buildNextFilename("Show.E03.mkv", null, 3, null, 4))
    }

    @Test
    fun movieFilenameReturnsNull() {
        assertNull(FilenameEpisodeMatcher.buildNextFilename("The.Matrix.1999.2160p.UHD.BluRay.mkv", null, 0, null, 0))
    }

    @Test
    fun resolution1920x1080IsNotMatchedAsSeasonXEpisode() {
        assertNull(FilenameEpisodeMatcher.buildNextFilename("Movie.1920x1080.BluRay.mkv", 1920, 1080, 1920, 1081))
    }

    @Test
    fun zeroPaddingPreserved() {
        assertEquals("Show.S01E10.mkv", FilenameEpisodeMatcher.buildNextFilename("Show.S01E03.mkv", 1, 3, 1, 10))
    }

    // --- extractSeasonEpisode (upstream) ---

    @Test
    fun extractSxxexx() {
        assertEquals(2 to 5, FilenameEpisodeMatcher.extractSeasonEpisode("Show.S02E05.1080p.mkv"))
    }

    @Test
    fun extract1x03() {
        assertEquals(1 to 3, FilenameEpisodeMatcher.extractSeasonEpisode("Show.1x03.DVDRip.mkv"))
    }

    @Test
    fun extractEpDot03() {
        assertEquals(null to 3, FilenameEpisodeMatcher.extractSeasonEpisode("Anime.EP.03.720p.mkv"))
    }

    @Test
    fun extractEp03() {
        assertEquals(null to 3, FilenameEpisodeMatcher.extractSeasonEpisode("Anime.EP03.720p.mkv"))
    }

    @Test
    fun extractReturnsNullForMovie() {
        assertNull(FilenameEpisodeMatcher.extractSeasonEpisode("The.Matrix.1999.mkv"))
    }

    @Test
    fun extractDoesNotMatch1920x1080() {
        assertNull(FilenameEpisodeMatcher.extractSeasonEpisode("Movie.1920x1080.mkv"))
    }

    // --- matches (upstream) ---

    @Test
    fun matchesIsCaseInsensitive() {
        assertTrue(FilenameEpisodeMatcher.matches("Show.S01E04.mkv", "show.s01e04.mkv"))
    }

    @Test
    fun matchesReturnsFalseForNull() {
        assertFalse(FilenameEpisodeMatcher.matches(null, "show.mkv"))
        assertFalse(FilenameEpisodeMatcher.matches("show.mkv", null))
    }

    // --- expectedNextFilename (fork) ---

    @Test
    fun expectedNextFilenameRewritesTheEpisodeToken() {
        assertEquals(
            "Show.S01E04.1080p.mkv",
            FilenameEpisodeMatcher.expectedNextFilename("Show.S01E03.1080p.mkv", 1, 3, 1, 4),
        )
    }

    @Test
    fun expectedNextFilenameCrossesTheSeasonBoundary() {
        assertEquals(
            "Show.S02E01.1080p.mkv",
            FilenameEpisodeMatcher.expectedNextFilename("Show.S01E10.1080p.mkv", 1, 10, 2, 1),
        )
    }

    @Test
    fun expectedNextFilenameIsNullWhenTheTokenDisagrees() {
        // Fork deviation (review r1): absolute numbering in the context, season numbering in the
        // file — the same-name fallback would match the current episode's file again.
        assertNull(FilenameEpisodeMatcher.expectedNextFilename("Show.S02E01.mkv", 1, 13, 1, 14))
    }

    @Test
    fun expectedNextFilenameFallsBackToTheSameNameOnlyWithoutAnyToken() {
        assertEquals("Show.Complete.Pack.mkv",
                     FilenameEpisodeMatcher.expectedNextFilename("Show.Complete.Pack.mkv", 1, 3, 1, 4))
    }

    @Test
    fun episodeOnlyNameNeverRewritesAcrossASeason() {
        // Fork deviation (review r1): E10 → E01 across S1 → S2 would be season 1's first episode.
        assertNull(FilenameEpisodeMatcher.expectedNextFilename("Show.S01.E10.mkv", 1, 10, 2, 1))
    }

    @Test
    fun expectedNextFilenameIsNullWithoutAFilename() {
        assertNull(FilenameEpisodeMatcher.expectedNextFilename(null, 1, 3, 1, 4))
        assertNull(FilenameEpisodeMatcher.expectedNextFilename("  ", 1, 3, 1, 4))
    }

    @Test
    fun expectedNextFilenameTreatsMissingEpisodeNumbersAsZero() {
        // Upstream passes `episode ?: 0`; with no episode number the token cannot match.
        // Fork deviation (review r1): the token is present but cannot match, so no same-name fallback.
        assertNull(FilenameEpisodeMatcher.expectedNextFilename("Show.S01E03.mkv", 1, null, 1, null))
    }

    // --- findMatch (fork) ---

    @Test
    fun findMatchPrefersTheSameBingeGroupAndFilename() {
        val otherGroupSameName = stream("A", bingeGroup = "group-b", filename = "Show.S01E04.mkv")
        val wanted = stream("B", bingeGroup = "group-a", filename = "Show.S01E04.mkv")
        val sameGroupOtherName = stream("C", bingeGroup = "group-a", filename = "Show.S01E04.720p.mkv")

        val match = FilenameEpisodeMatcher.findMatch(
            listOf(otherGroupSameName, sameGroupOtherName, wanted),
            expectedFilename = "show.s01e04.mkv",
            bingeGroup = "group-a",
        )

        assertSame(wanted, match)
    }

    @Test
    fun findMatchWithoutABingeGroupTakesAnyGroupInListOrder() {
        val first = stream("A", bingeGroup = "group-b", filename = "Show.S01E04.mkv")
        val second = stream("B", bingeGroup = "group-a", filename = "Show.S01E04.mkv")

        assertSame(first, FilenameEpisodeMatcher.findMatch(listOf(first, second), "Show.S01E04.mkv", bingeGroup = null))
        assertSame(first, FilenameEpisodeMatcher.findMatch(listOf(first, second), "Show.S01E04.mkv", bingeGroup = "  "))
    }

    @Test
    fun findMatchNeedsAnExpectedFilenameAndADeclaredOne() {
        val noName = stream("A", bingeGroup = "group-a", filename = null)
        assertNull(FilenameEpisodeMatcher.findMatch(listOf(noName), "Show.S01E04.mkv", "group-a"))
        assertNull(FilenameEpisodeMatcher.findMatch(listOf(noName), null, "group-a"))
    }

    @Test
    fun findMatchIgnoresTheAutoPlaySourceScope() {
        // Upstream d293973bd: same-release matching is not limited by the auto-play source or
        // add-on filters, so a plugin stream matches even though no filter was consulted.
        val plugin = stream("Some Plugin", bingeGroup = null, filename = "Show.S01E04.mkv")
        assertSame(plugin, FilenameEpisodeMatcher.findMatch(listOf(plugin), "Show.S01E04.mkv", null))
    }

    // --- findInfoHashMatch (upstream d2cc0fb8a) ---

    @Test
    fun findInfoHashMatchTakesTheSameGroupAndHashIgnoringCase() {
        val otherGroup = hashStream("A", bingeGroup = "group-b", infoHash = "ABCDEF0123")
        val wanted = hashStream("B", bingeGroup = "group-a", infoHash = "abcdef0123")
        assertSame(wanted, FilenameEpisodeMatcher.findInfoHashMatch(listOf(otherGroup, wanted), "ABCDEF0123", "group-a"))
    }

    @Test
    fun findInfoHashMatchNeedsTheSameBingeGroup() {
        val s = hashStream("A", bingeGroup = "group-b", infoHash = "abcdef0123")
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(s), "abcdef0123", "group-a"))
    }

    @Test
    fun findInfoHashMatchNeedsANonBlankGroup() {
        val s = hashStream("A", bingeGroup = null, infoHash = "abcdef0123")
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(s), "abcdef0123", null))
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(s), "abcdef0123", "  "))
    }

    @Test
    fun findInfoHashMatchNeedsAHash() {
        val noHash = hashStream("A", bingeGroup = "group-a", infoHash = null)
        val withHash = hashStream("B", bingeGroup = "group-a", infoHash = "abcdef0123")
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(noHash, withHash), null, "group-a"))
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(noHash, withHash), "  ", "group-a"))
        assertNull(FilenameEpisodeMatcher.findInfoHashMatch(listOf(noHash), "abcdef0123", "group-a"))
    }

    @Test
    fun findInfoHashMatchReadsClientResolveAndMagnetHashes() {
        val resolve = hashStream(
            "A", bingeGroup = "group-a", infoHash = null,
            clientResolve = StreamClientResolve(infoHash = "1111AAAA"),
        )
        val magnet = hashStream(
            "B", bingeGroup = "group-a", infoHash = null,
            externalUrl = "magnet:?xt=urn:btih:2222BBBB&dn=Show",
        )
        assertSame(resolve, FilenameEpisodeMatcher.findInfoHashMatch(listOf(resolve, magnet), "1111aaaa", "group-a"))
        assertSame(magnet, FilenameEpisodeMatcher.findInfoHashMatch(listOf(resolve, magnet), "2222bbbb", "group-a"))
    }

    @Test
    fun findInfoHashMatchTakesTheFirstInListOrder() {
        val first = hashStream("A", bingeGroup = "group-a", infoHash = "abcdef0123")
        val second = hashStream("B", bingeGroup = "group-a", infoHash = "abcdef0123")
        assertSame(first, FilenameEpisodeMatcher.findInfoHashMatch(listOf(first, second), "abcdef0123", "group-a"))
    }

    private fun hashStream(
        addonName: String,
        bingeGroup: String?,
        infoHash: String?,
        clientResolve: StreamClientResolve? = null,
        externalUrl: String? = null,
    ) = StreamItem(
        name = "$addonName stream",
        url = null,
        infoHash = infoHash,
        externalUrl = externalUrl,
        clientResolve = clientResolve,
        addonName = addonName,
        addonId = addonName.lowercase(),
        behaviorHints = StreamBehaviorHints(bingeGroup = bingeGroup),
    )

    private fun stream(addonName: String, bingeGroup: String?, filename: String?) = StreamItem(
        name = "$addonName stream",
        url = "https://example.com/$addonName.mkv",
        addonName = addonName,
        addonId = addonName.lowercase(),
        behaviorHints = StreamBehaviorHints(bingeGroup = bingeGroup, filename = filename),
    )
}
