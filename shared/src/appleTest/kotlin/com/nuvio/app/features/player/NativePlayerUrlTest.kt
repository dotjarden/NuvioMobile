package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** FEAT-78: the Native Player deep link, per the developer's Infuse-compatible reference. */
class NativePlayerUrlTest {

    private fun request(
        sourceUrl: String = "https://cdn.example.com/a b.mkv?token=x&y=1",
        resumePositionMs: Long = 0L,
        subtitles: List<SubtitleInput>? = null,
        success: String? = "nuviotv-x://external-player/nativeplayer/s1/success",
    ) = ExternalPlayerPlaybackRequest(
        sourceUrl = sourceUrl,
        title = "Lizzie Borden",
        resumePositionMs = resumePositionMs,
        subtitles = subtitles,
        callbackSuccessUrl = success,
        callbackErrorUrl = success?.replace("success", "error"),
    )

    private fun query(url: String): List<Pair<String, String>> =
        url.substringAfter('?').split('&').map { it.substringBefore('=') to it.substringAfter('=') }

    @Test
    fun buildsTheDocumentedPlayUrlWithEverythingEncoded() {
        val url = buildNativePlayerUrl(request(resumePositionMs = 125_900L))
        assertTrue(url.startsWith("nativeplayer://x-callback-url/play?url="))
        val params = query(url)
        assertEquals("https%3A%2F%2Fcdn.example.com%2Fa%20b.mkv%3Ftoken%3Dx%26y%3D1", params.first { it.first == "url" }.second)
        assertEquals("125", params.first { it.first == "position" }.second)
        assertTrue(params.any { it.first == "filename" })
        assertTrue(params.any { it.first == "x-success" })
        assertTrue(params.any { it.first == "x-error" })
    }

    @Test
    fun omitsPositionAtTheStart() {
        assertFalse(query(buildNativePlayerUrl(request(resumePositionMs = 0L))).any { it.first == "position" })
    }

    @Test
    fun sendsOnlyHttpSrtCompatibleSubtitlesUpToEight() {
        val subs = listOf(
            SubtitleInput("https://subs.example.com/1.srt", "en", "en"),
            SubtitleInput("https://subs.example.com/2.vtt", "en", "en"),
            SubtitleInput("https://subs.example.com/3.ass?x=1", "en", "en"),
            SubtitleInput("file:///local/4.srt", "en", "en"),
            SubtitleInput("https://opensubtitles.example.com/file/5", "fr", "fr"),
        ) + (6..15).map { SubtitleInput("https://subs.example.com/$it.srt", "de", "de") }
        val sent = query(buildNativePlayerUrl(request(subtitles = subs))).filter { it.first == "sub" }
        assertEquals(8, sent.size)
        assertTrue(sent[0].second.endsWith("1.srt"))
        assertTrue(sent[1].second.endsWith("file%2F5"))
        assertFalse(sent.any { it.second.contains("vtt") || it.second.contains("ass") || it.second.startsWith("file") })
    }

    @Test
    fun refusesNonHttpAndDashSources() {
        assertTrue(nativePlayerSupportsSource("https://cdn.example.com/movie.mkv"))
        assertTrue(nativePlayerSupportsSource("HTTP://cdn.example.com/master.m3u8"))
        assertFalse(nativePlayerSupportsSource("https://cdn.example.com/manifest.MPD?sig=1"))
        assertFalse(nativePlayerSupportsSource("https://cdn.example.com/stream.mpd#t=30"))
        assertFalse(nativePlayerSupportsSource("magnet:?xt=urn:btih:abc"))
        assertFalse(nativePlayerSupportsSource("file:///tmp/a.mkv"))
    }
}
