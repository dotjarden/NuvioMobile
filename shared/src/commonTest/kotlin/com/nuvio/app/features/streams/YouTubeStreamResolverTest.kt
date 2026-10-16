package com.nuvio.app.features.streams

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertSame

/**
 * Upstream 94976222's `YouTubeStreamResolverTest`, adapted to the fork's shape: the logic sits in
 * [YouTubeStreamResolverCore] (constructor-injected extractor) under the Swift-facing `object`.
 * Upstream's "without in-app playback the watch page opens externally" case is dropped: tvOS has
 * no App Store flavor, so that branch does not exist here.
 */
class YouTubeStreamResolverTest {

    private val videoId = "dQw4w9WgXcQ"
    private val watchUrl = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    private val manifestUrl = "https://manifest.googlevideo.com/api/manifest/hls_variant/id/1/file/index.m3u8"

    @Test
    fun `watch url is built from the video id`() {
        assertEquals(watchUrl, YouTubeStreamResolverCore.watchUrl(videoId))
        assertEquals(watchUrl, YouTubeStreamResolver.watchUrl(videoId))
    }

    @Test
    fun `resolves the watch url and sets only the stream url`() = runTest {
        val requested = mutableListOf<String>()
        val resolver = YouTubeStreamResolverCore { url ->
            requested += url
            manifestUrl
        }
        val stream = ytIdStream()

        val resolved = resolver.resolve(stream)

        assertEquals(listOf(watchUrl), requested)
        assertEquals(stream.copy(url = manifestUrl), resolved)
        assertEquals(manifestUrl, resolved?.playableDirectUrl)
        assertNull(resolved?.youTubeIdToResolve)
    }

    @Test
    fun `resolved url is trimmed`() = runTest {
        val resolver = YouTubeStreamResolverCore { " $manifestUrl\n" }
        assertEquals(manifestUrl, resolver.resolve(ytIdStream())?.url)
    }

    @Test
    fun `resolves the trimmed id`() = runTest {
        val requested = mutableListOf<String>()
        val resolver = YouTubeStreamResolverCore { url ->
            requested += url
            manifestUrl
        }
        resolver.resolve(ytIdStream(ytId = "  $videoId "))
        assertEquals(listOf(watchUrl), requested)
    }

    @Test
    fun `failed extraction returns null`() = runTest {
        val resolver = YouTubeStreamResolverCore { null }
        assertNull(resolver.resolve(ytIdStream()))
    }

    @Test
    fun `a failing extractor yields null from the null-mapping resolve`() = runTest {
        val resolver = YouTubeStreamResolverCore { throw IllegalStateException("boom") }
        assertNull(resolver.resolveOrNull(ytIdStream()))
    }

    @Test
    fun `cancellation propagates out of the null-mapping resolve`() = runTest {
        val resolver = YouTubeStreamResolverCore { throw CancellationException("cancelled") }
        assertFailsWith<CancellationException> { resolver.resolveOrNull(ytIdStream()) }
    }

    @Test
    fun `blank extraction returns null`() = runTest {
        val resolver = YouTubeStreamResolverCore { "   " }
        assertNull(resolver.resolve(ytIdStream()))
    }

    @Test
    fun `streams that do not need resolving are returned untouched`() = runTest {
        var calls = 0
        val resolver = YouTubeStreamResolverCore {
            calls++
            manifestUrl
        }
        val direct = ytIdStream().copy(url = "https://example.com/video.mp4")
        val external = ytIdStream().copy(externalUrl = "https://example.com/watch")
        val torrent = ytIdStream().copy(infoHash = "0123456789abcdef0123456789abcdef01234567")
        val plain = ytIdStream(ytId = null).copy(url = "https://example.com/video.mp4")

        assertSame(direct, resolver.resolve(direct))
        assertSame(external, resolver.resolve(external))
        assertSame(torrent, resolver.resolve(torrent))
        assertSame(plain, resolver.resolve(plain))
        assertEquals(0, calls)
    }

    @Test
    fun `the Swift-facing object returns a stream that needs no resolving without extracting`() = runTest {
        val plain = ytIdStream(ytId = null).copy(url = "https://example.com/video.mp4")
        assertSame(plain, YouTubeStreamResolver.resolve(plain))
    }

    private fun ytIdStream(ytId: String? = videoId): StreamItem = StreamItem(
        name = "YouTube",
        description = "Watch on YouTube",
        ytId = ytId,
        addonName = "TestAddon",
        addonId = "test.addon",
        behaviorHints = StreamBehaviorHints(bingeGroup = "yt"),
    )
}
