package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Stream picker A, P0.4: [StreamFactsParser] over three rows as the add-ons actually send them,
 * transcribed from device shots in the outer repo:
 *  - Torrentio: `docs/research/batch-b-device-2026-10-16/r3-picker.jpg` (Lizzie Borden Took an Ax)
 *  - Comet: `docs/research/wave3-device-pass-2026-10-21/40-picker.png` (Animals, 2026)
 *  - AIOStreams: `docs/research/wave3-device-pass-2026-10-21/01-picker.png` (Animals, 2026)
 * The `name` is the add-on's raw one (the picker shows it after the debrid "Instant" formatter);
 * `description` is the row caption verbatim, emoji included.
 */
class StreamFactsParserTest {

    @Test
    fun torrentioRow() {
        val stream = StreamItem(
            name = "[TB+] Torrentio\n1080p",
            description = "Lizzie.Borden.Took.an.Ax.2014.1080p.WEBRip.x264-RARBG\n👤 3 💾 1.66 GB ⚙️ RARBG",
            url = "https://torrentio.strem.fun/torbox/resolve/abc",
            addonName = "Torrentio",
            addonId = "addon:com.stremio.torrentio.addon",
            behaviorHints = StreamBehaviorHints(
                filename = "Lizzie.Borden.Took.an.Ax.2014.1080p.WEBRip.x264-RARBG.mkv",
                videoSize = 1_782_579_200L,
            ),
        )

        val facts = StreamFactsParser.parse(stream)

        assertEquals(1080, facts.resolution)
        assertNull(facts.hdr)
        assertEquals("WEBRip", facts.sourceType)
        assertEquals("AVC", facts.codec)
        assertNull(facts.audio)
        assertEquals(1_782_579_200L, facts.sizeBytes)
        // A resolved http link from the add-on: not a debrid candidate the app has to resolve.
        assertNull(facts.cached)
        assertEquals(emptyList(), facts.languages)
    }

    @Test
    fun torrentioRowWithFlags() {
        val stream = StreamItem(
            name = "[TB+] Torrentio\n1080p",
            description = "Лиззи Борден взяла топор / Lizzie Borden Took an Ax [2014 WEB-DL 1080p] MVO (iTunes) + 2x Sub (Eng) + Original Eng\n👤 5 💾 7.91 GB ⚙️ Rutracker\n🇬🇧 / 🇷🇺",
            url = "https://torrentio.strem.fun/torbox/resolve/def",
            addonName = "Torrentio",
            addonId = "addon:com.stremio.torrentio.addon",
            behaviorHints = StreamBehaviorHints(videoSize = 8_493_465_600L),
        )

        val facts = StreamFactsParser.parse(stream)

        assertEquals(1080, facts.resolution)
        assertEquals("WEB-DL", facts.sourceType)
        assertEquals(listOf("en", "ru"), facts.languages)
    }

    @Test
    fun cometRow() {
        val stream = StreamItem(
            name = "[TB⚡] Comet\n2160p",
            description = "📄 Animals.2026.2160p.NF.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-XEBEC\n" +
                "📹 hevc • DV • HDR | 🔊 Atmos • Dolby Digital Plus • 5.1\n" +
                "⭐ WEB-DL | 🏷️ XEBEC\n" +
                "💾 12.2 GB 🔎 StremThru",
            url = "https://comet.example/playback/torbox/xyz",
            addonName = "Comet",
            addonId = "addon:comet.elfhosted.com",
            behaviorHints = StreamBehaviorHints(
                filename = "Animals.2026.2160p.NF.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-XEBEC.mkv",
                videoSize = 13_099_000_000L,
            ),
        )

        val facts = StreamFactsParser.parse(stream)

        assertEquals(2160, facts.resolution)
        assertEquals("DV HDR", facts.hdr)
        assertEquals("WEB-DL", facts.sourceType)
        assertEquals("HEVC", facts.codec)
        assertEquals("Atmos DD+ 5.1", facts.audio)
        assertEquals(13_099_000_000L, facts.sizeBytes)
        assertNull(facts.cached)
        assertEquals(emptyList(), facts.languages)
    }

    @Test
    fun aioStreamsRow() {
        val stream = StreamItem(
            name = "4K ⭐⭐⭐⭐ ⚡",
            description = "🎬 Animals (2026)\n" +
                "🟢 INSTANT PLAY\n" +
                "──────────────\n" +
                "Languages: 🇬🇧,🇪🇸,🇫🇷,🇩🇪,🇮🇹\n" +
                "✨ Streaming Quality | 🎥 Dolby Vision | 🔊 Atmos, DD+\n" +
                "──────────────\n" +
                "📁 16.38 GB | ☁️ TorBox | 🪐 Comet",
            url = "https://aiostreams.example/stream/play/abc",
            addonName = "AIO Streams",
            addonId = "addon:aiostreams.viren070.me",
            behaviorHints = StreamBehaviorHints(videoSize = 16_380_000_000L),
        )

        val facts = StreamFactsParser.parse(stream)

        assertEquals(2160, facts.resolution)
        assertEquals("DV", facts.hdr)
        // "Streaming Quality" is AIOStreams' own wording, not a source type the parser knows.
        assertNull(facts.sourceType)
        assertNull(facts.codec)
        assertEquals("Atmos DD+", facts.audio)
        assertEquals(16_380_000_000L, facts.sizeBytes)
        assertEquals(listOf("en", "es", "fr", "de", "it"), facts.languages)
    }

    @Test
    fun cachedReflectsTheDebridCandidateState() {
        val cachedTorrent = StreamItem(
            name = "Torrentio\n2160p",
            infoHash = "0123456789abcdef0123456789abcdef01234567",
            addonName = "Torrentio",
            addonId = "addon:torrentio",
            debridCacheStatus = StreamDebridCacheStatus(
                providerId = "torbox",
                providerName = "TorBox",
                state = StreamDebridCacheState.CACHED,
                cachedSize = 5_000L,
            ),
        )
        val uncachedTorrent = cachedTorrent.copy(debridCacheStatus = null)

        assertEquals(true, StreamFactsParser.parse(cachedTorrent).cached)
        assertEquals(5_000L, StreamFactsParser.parse(cachedTorrent).sizeBytes)
        assertEquals(false, StreamFactsParser.parse(uncachedTorrent).cached)
    }

    @Test
    fun bestCandidateFollowsTheFilterAndTheQualityRank() {
        val comet1080 = plain("Comet 1080p WEB-DL", addon = "addon:comet", size = GB * 4)
        val comet2160 = plain("Comet 2160p WEB-DL HDR10", addon = "addon:comet", size = GB * 20)
        val torrentio2160Dv = plain("Torrentio 2160p BluRay REMUX DV HDR", addon = "addon:torrentio", size = GB * 60)
        val groups = listOf(
            AddonStreamGroup(addonName = "Comet", addonId = "addon:comet", streams = listOf(comet1080, comet2160)),
            AddonStreamGroup(addonName = "Torrentio", addonId = "addon:torrentio", streams = listOf(torrentio2160Dv)),
        )

        val all = StreamsUiState(groups = groups)
        assertEquals(torrentio2160Dv, all.bestCandidate)
        assertEquals(comet2160, all.copy(selectedFilter = "addon:comet").bestCandidate)
        assertNull(StreamsUiState().bestCandidate)
        assertNull(all.copy(selectedFilter = "addon:gone").bestCandidate)
    }

    private fun plain(name: String, addon: String, size: Long): StreamItem = StreamItem(
        name = name,
        url = "https://example.com/${name.replace(' ', '-')}.mkv",
        addonName = addon,
        addonId = addon,
        behaviorHints = StreamBehaviorHints(videoSize = size),
    )

    private companion object {
        const val GB = 1_000_000_000L
    }

    private fun audioOf(description: String): String? = StreamFactsParser.parse(
        StreamItem(
            name = "Test",
            description = description,
            url = "https://example.com/play",
            addonName = "Test",
            addonId = "test",
        ),
    ).audio

    @Test
    fun dtsHdMaKeepsOnlyTheMostSpecificTag() {
        assertEquals("DTS-HD MA 7.1", audioOf("Movie.2020.2160p.BluRay.DTS-HD MA 7.1-GRP"))
    }

    @Test
    fun dtsHdDropsPlainDts() {
        assertEquals("DTS-HD 5.1", audioOf("Movie.2020.1080p.BluRay.DTS-HD 5.1-GRP"))
    }

    @Test
    fun dtsXDropsPlainDts() {
        assertEquals("DTS:X 7.1", audioOf("Movie.2020.2160p.BluRay.DTS:X 7.1-GRP"))
    }

    @Test
    fun plainDtsIsKept() {
        assertEquals("DTS 5.1", audioOf("Movie.2020.1080p.BluRay.DTS 5.1-GRP"))
    }
}
