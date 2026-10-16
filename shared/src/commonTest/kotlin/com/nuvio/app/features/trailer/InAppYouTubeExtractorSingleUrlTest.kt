package com.nuvio.app.features.trailer

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Upstream 94976222's `InAppYouTubeExtractorSingleUrlTest` (an Android host test there). The
 * fork's `ManifestCandidate` carries an extra `isSdr` default; the `TrailerPlaybackResolver`
 * assertion is dropped because tvOS resolves through `HeroTrailerResolver`/`YouTubeStreamResolver`.
 */
class InAppYouTubeExtractorSingleUrlTest {

    private val extractor = InAppYouTubeExtractor()

    @Test
    fun `single url mode uses the master playlist rather than the best variant`() {
        val manifest = ManifestCandidate(
            client = "ios",
            priority = 2,
            manifestUrl = "https://manifest.googlevideo.com/api/manifest/hls_variant/index.m3u8",
            selectedVariantUrl = "https://manifest.googlevideo.com/api/manifest/hls_playlist/itag/137/index.m3u8",
            height = 1080,
            bandwidth = 4_000_000,
        )

        assertEquals(manifest.manifestUrl, extractor.selectSingleUrlManifest(manifest))
    }

    @Test
    fun `single url mode has no manifest when there is none or it is blank`() {
        assertNull(extractor.selectSingleUrlManifest(null))
        val blank = ManifestCandidate(
            client = "ios",
            priority = 2,
            manifestUrl = "  ",
            selectedVariantUrl = "https://example.com/variant.m3u8",
            height = 720,
            bandwidth = 1,
        )
        assertNull(extractor.selectSingleUrlManifest(blank))
    }

    @Test
    fun `blank input resolves to nothing without a network call`() = runTest {
        assertNull(extractor.extractSingleUrl(""))
        assertNull(extractor.extractSingleUrl("   "))
    }
}
