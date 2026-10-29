package com.nuvio.app.features.debrid

import com.nuvio.app.features.streams.AddonStreamGroup
import com.nuvio.app.features.streams.StreamBehaviorHints
import com.nuvio.app.features.streams.StreamClientResolve
import com.nuvio.app.features.streams.StreamClientResolveParsed
import com.nuvio.app.features.streams.StreamClientResolveRaw
import com.nuvio.app.features.streams.StreamClientResolveStream
import com.nuvio.app.features.streams.StreamDebridCacheState
import com.nuvio.app.features.streams.StreamDebridCacheStatus
import com.nuvio.app.features.streams.StreamItem
import kotlin.test.Test
import kotlin.test.assertEquals

class DebridStreamPresentationLanguageTest {
    @Test
    fun `reads languages from release name words when the stream has no parsed languages`() {
        fun languages(filename: String) = DebridStreamMetadata.facts(
            stream = localTorboxStream(filename = filename, size = 1_000_000_000),
            preferences = DebridStreamPreferences(),
        ).languages

        assertEquals(
            listOf(DebridStreamLanguage.EN, DebridStreamLanguage.IT),
            languages("Movie.2023.1080p.WEB-DL.ITA.ENG.x264-GRP.mkv"),
        )
        assertEquals(listOf(DebridStreamLanguage.FR), languages("Movie.2023.TRUEFRENCH.1080p.WEB-DL.x265-GRP.mkv"))
        assertEquals(listOf(DebridStreamLanguage.FR), languages("Movie.2023.FRENCH.1080p.WEB-DL.x265-GRP.mkv"))
        assertEquals(listOf(DebridStreamLanguage.DE), languages("Movie.2023.German.DL.1080p.BluRay.x264-GRP.mkv"))
        assertEquals(listOf(DebridStreamLanguage.ES), languages("Movie (2023) [BluRay][Castellano].mkv"))
        assertEquals(listOf(DebridStreamLanguage.MULTI), languages("Movie.2023.MULTI.1080p.BluRay.x264-GRP.mkv"))
        assertEquals(emptyList(), languages("Por.Siempre.2023.1080p.WEB-DL.x264-GRP.mkv"))
        assertEquals(emptyList(), languages("Movie.2023.1080p.WEB-DL.x264-GRP.mkv"))
    }

    @Test
    fun `accepts release name words in parsed languages`() {
        val stream = premiumizeDirectStream(
            name = "PM Instant",
            filename = "Movie.2023.2160p.WEB-DL.H265.mkv",
            size = 12_000_000_000,
        ).let { stream ->
            val resolve = stream.clientResolve!!
            val raw = resolve.stream!!.raw!!
            stream.copy(
                clientResolve = resolve.copy(
                    stream = StreamClientResolveStream(
                        raw = raw.copy(parsed = raw.parsed!!.copy(languages = listOf("ita", "Eng", "klingon"))),
                    ),
                ),
            )
        }

        val languages = DebridStreamMetadata.facts(stream, DebridStreamPreferences()).languages

        assertEquals(listOf(DebridStreamLanguage.IT, DebridStreamLanguage.EN), languages)
    }

    @Test
    fun `required language keeps streams whose release name only has the language word`() {
        val italian = localTorboxStream(name = "First", filename = "Movie.2023.1080p.WEB-DL.ITA.x264-GRP.mkv", size = 1_000_000_000)
        val english = localTorboxStream(name = "Second", filename = "Movie.2023.1080p.WEB-DL.ENG.x264-GRP.mkv", size = 2_000_000_000)

        val result = DebridStreamPresentation.applyPreferences(
            streams = listOf(italian, english),
            settings = DebridSettings(
                enabled = true,
                providerApiKeys = mapOf(DebridProviders.TORBOX_ID to "key"),
                streamPreferences = DebridStreamPreferences(requiredLanguages = listOf(DebridStreamLanguage.IT)),
            ),
        )

        assertEquals(listOf("First"), result.map { it.name })
    }

    @Test
    fun `does not read title words as the stream language`() {
        fun languages(filename: String, title: String) = DebridStreamMetadata.facts(
            stream = premiumizeDirectStream(name = "PM Instant", filename = filename, size = 1_000_000_000, title = title),
            preferences = DebridStreamPreferences(),
        ).languages

        assertEquals(emptyList(), languages("The.French.Dispatch.2021.1080p.BluRay.x264-GRP.mkv", "The French Dispatch"))
        assertEquals(
            listOf(DebridStreamLanguage.EN),
            languages("The.Italian.Job.2003.1080p.BluRay.ENG.x264-GRP.mkv", "The Italian Job"),
        )
        assertEquals(
            listOf(DebridStreamLanguage.IT),
            languages("The Italian Job (2003) 1080p BluRay ITA AC3.mkv", "The Italian Job"),
        )
        assertEquals(listOf(DebridStreamLanguage.FR), languages("French.2020.FRENCH.1080p.WEB-DL.x264-GRP.mkv", "French"))
    }

    @Test
    fun `does not read the parsed title as the stream language`() {
        val stream = premiumizeDirectStream(
            name = "PM Instant",
            filename = "The.French.Dispatch.2021.1080p.BluRay.ITA.x264-GRP.mkv",
            size = 1_000_000_000,
        ).let { stream ->
            val resolve = stream.clientResolve!!
            val raw = resolve.stream!!.raw!!
            stream.copy(
                clientResolve = resolve.copy(
                    stream = StreamClientResolveStream(
                        raw = raw.copy(parsed = raw.parsed!!.copy(parsedTitle = "The French Dispatch")),
                    ),
                ),
            )
        }

        val languages = DebridStreamMetadata.facts(stream, DebridStreamPreferences()).languages

        assertEquals(listOf(DebridStreamLanguage.IT), languages)
    }

    @Test
    fun `required language hides streams whose title only has the language word`() {
        val italianTitle = premiumizeDirectStream(
            name = "First",
            filename = "The.Italian.Job.2003.1080p.BluRay.ENG.x264-GRP.mkv",
            size = 1_000_000_000,
            title = "The Italian Job",
        )
        val italianAudio = premiumizeDirectStream(
            name = "Second",
            filename = "The.Italian.Job.2003.1080p.BluRay.ITA.x264-GRP.mkv",
            size = 2_000_000_000,
            title = "The Italian Job",
        )

        val result = DebridStreamPresentation.applyPreferences(
            streams = listOf(italianTitle, italianAudio),
            settings = DebridSettings(
                enabled = true,
                providerApiKeys = mapOf(DebridProviders.PREMIUMIZE_ID to "key"),
                streamPreferences = DebridStreamPreferences(requiredLanguages = listOf(DebridStreamLanguage.IT)),
            ),
        )

        assertEquals(listOf("Second"), result.map { it.name })
    }

    @Test
    fun `allStreams without a resolver keeps a passthrough stream whose name has the required language word`() {
        val italian = StreamItem(
            name = "Movie.2024.1080p.ITA.ENG",
            url = "https://example.test/italian.mkv",
            addonName = "Addon",
            addonId = "addon:test",
        )
        val french = StreamItem(
            name = "Movie.2024.1080p.FRENCH",
            url = "https://example.test/french.mkv",
            addonName = "Addon",
            addonId = "addon:test",
        )
        val groups = listOf(
            AddonStreamGroup(addonName = "Addon", addonId = "addon:test", streams = listOf(italian, french)),
        )

        val result = DebridStreamPresentation.apply(
            groups = groups,
            settings = DebridSettings(
                enabled = false,
                streamPreferences = DebridStreamPreferences(requiredLanguages = listOf(DebridStreamLanguage.IT)),
            ),
            allStreams = true,
        ).single().streams

        assertEquals(listOf("Movie.2024.1080p.ITA.ENG"), result.map { it.name })
    }

    @Test
    fun `formats filtered debrid streams with the facts computed while filtering`() {
        val settings = DebridSettings(
            enabled = true,
            providerApiKeys = mapOf(DebridProviders.TORBOX_ID to "key"),
            streamPreferences = DebridStreamPreferences(excludedEncodes = listOf(DebridStreamEncode.AVC)),
            streamNameTemplate = "{stream.resolution} {stream.quality} {stream.encode}",
            streamDescriptionTemplate = "{stream.filename}",
        )
        val passthrough = StreamItem(
            name = "Regular",
            url = "https://example.com/movie.mkv",
            addonName = "Addon",
            addonId = "addon:test",
        )
        val debridStreams = listOf(
            localTorboxStream(filename = "Movie.2023.1080p.WEB-DL.DDP5.1.x265-GRP.mkv", size = 4_000_000_000),
            localTorboxStream(filename = "Movie.2023.2160p.BluRay.Remux.DV.HDR.HEVC.DTS-HD.MA-SGF.mkv", size = 40_000_000_000),
            localTorboxStream(filename = "Movie.2023.720p.WEBRip.AAC.x264-GRP.mkv", size = 1_000_000_000),
            localTorboxStream(filename = "Movie.2023.1440p.HDTV.HDR.AV1.mkv", size = 6_000_000_000),
        )

        val presented = DebridStreamPresentation.apply(
            groups = listOf(
                AddonStreamGroup(
                    addonName = "Addon",
                    addonId = "addon:test",
                    streams = debridStreams + passthrough,
                ),
            ),
            settings = settings,
        ).single().streams

        val formatter = DebridStreamFormatter()
        val expectedDebrid = DebridStreamPresentation.applyPreferences(debridStreams, settings)
            .map { formatter.format(it, settings) }
        assertEquals(expectedDebrid + passthrough, presented)
        assertEquals(
            listOf("1080p WEB-DL HEVC", "2160p BluRay REMUX HEVC", "1440p HDTV AV1"),
            presented.dropLast(1).map { it.name },
        )
    }

    private fun localTorboxStream(
        name: String = "Torrent",
        filename: String,
        size: Long,
        cacheState: StreamDebridCacheState = StreamDebridCacheState.CACHED,
    ): StreamItem =
        StreamItem(
            name = name,
            infoHash = "abcdef1234567890abcdef1234567890abcdef12$size".take(40),
            addonName = "Addon",
            addonId = "addon:test",
            behaviorHints = StreamBehaviorHints(
                filename = filename,
                videoSize = size,
            ),
            debridCacheStatus = StreamDebridCacheStatus(
                providerId = DebridProviders.TORBOX_ID,
                providerName = DebridProviders.Torbox.displayName,
                state = cacheState,
                cachedName = filename,
                cachedSize = size,
            ),
        )

    private fun premiumizeDirectStream(
        name: String,
        filename: String,
        size: Long,
        title: String? = null,
    ): StreamItem =
        StreamItem(
            name = name,
            addonName = "Torrentio",
            addonId = "addon:torrentio",
            clientResolve = StreamClientResolve(
                type = "debrid",
                service = DebridProviders.PREMIUMIZE_ID,
                filename = filename,
                title = title,
                isCached = true,
                stream = StreamClientResolveStream(
                    raw = StreamClientResolveRaw(
                        filename = filename,
                        size = size,
                        parsed = StreamClientResolveParsed(
                            resolution = "2160p",
                        ),
                    ),
                ),
            ),
        )
}
