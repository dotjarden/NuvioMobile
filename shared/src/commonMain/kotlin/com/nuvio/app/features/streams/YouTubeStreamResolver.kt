package com.nuvio.app.features.streams

import com.nuvio.app.features.trailer.InAppYouTubeExtractor

/**
 * Makes streams that only carry a YouTube id ([StreamItem.ytId]) playable (upstream 94976222).
 *
 * The video is resolved on the device to one URL the player can open (the HLS master playlist,
 * else a progressive file). Fork: tvOS has no App Store flavor, so upstream's "open the watch page
 * externally" branch does not exist here (see [com.nuvio.app.features.trailer.HeroTrailerResolver]
 * for the same stance on trailers); the logic lives in [YouTubeStreamResolverCore] so it can be
 * unit-tested with a fake extractor, and this `object` is what Swift calls:
 * `YouTubeStreamResolver.shared.resolve(stream:) { resolved, error in ... }`.
 *
 * The resolved URL expires after a few hours: callers must not persist it (reuse-last-link cache,
 * rejected-link memory).
 */
object YouTubeStreamResolver {
    private val core by lazy {
        val extractor = InAppYouTubeExtractor()
        YouTubeStreamResolverCore { url -> extractor.extractSingleUrl(url) }
    }

    /**
     * Returns [stream] unchanged when it needs no resolving, a copy whose `url` is the extracted
     * single URL when it does, or null when the video could not be resolved. Never throws: a Kotlin
     * exception out of a plain suspend export aborts the process on tvOS.
     */
    suspend fun resolve(stream: StreamItem): StreamItem? =
        runCatching { core.resolve(stream) }.getOrNull()

    fun watchUrl(videoId: String): String = YouTubeStreamResolverCore.watchUrl(videoId)
}

internal class YouTubeStreamResolverCore(
    private val extractSingleUrl: suspend (String) -> String?,
) {
    suspend fun resolve(stream: StreamItem): StreamItem? {
        val videoId = stream.youTubeIdToResolve ?: return stream
        val url = extractSingleUrl(watchUrl(videoId))?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return stream.copy(url = url)
    }

    companion object {
        fun watchUrl(videoId: String): String = "https://www.youtube.com/watch?v=$videoId"
    }
}
