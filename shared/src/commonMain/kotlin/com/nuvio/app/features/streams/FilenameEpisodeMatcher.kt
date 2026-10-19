package com.nuvio.app.features.streams

/**
 * Filename-based next-episode stream matching, ported from NuvioTV (Android TV)
 * `core/player/FilenameEpisodeMatcher.kt`: upstream 953938c72 ("filename matching for binge group
 * stream selection") with the 829f0bbd9 regex fix (`(?<!\d)(\d{1,2})x…`, so `1920x1080` is never
 * read as season 1920 episode 1080). The three pattern objects, `buildNextFilename`, `matches` and
 * `extractSeasonEpisode` are verbatim.
 *
 * The idea: the playing stream's `behaviorHints.filename` (`Show.S01E03.1080p.WEB-DL.mkv`) names
 * its release; rewrite its episode token to the next episode (`Show.S01E04.1080p.WEB-DL.mkv`) and
 * look for a next-episode stream carrying exactly that filename. That finds the same release when
 * the add-on's `bingeGroup` changed between episodes or is missing.
 *
 * Fork additions below the verbatim part: [expectedNextFilename] (upstream's inline
 * `buildNextFilename(...) ?: currentFilename` in `PlayerRuntimeControllerStreams.playNextEpisode`)
 * and [findMatch] (its inline `firstOrNull { bingeGroup == … && matches(filename, …) }`), so the
 * tvOS Up Next engine (`NextEpisodeAutoPlay.swift`) calls one tested function instead of
 * re-implementing either.
 */
object FilenameEpisodeMatcher {

    /**
     * Recognized patterns (case-insensitive):
     *  - S01E03, S1E3, s01e03
     *  - S 01 E 03, S 1 E 3
     *  - 1x03, 01x03
     *  - E03, EP03, Ep 03, EP.03 (episode-only, no season)
     */
    fun buildNextFilename(
        filename: String,
        currentSeason: Int?,
        currentEpisode: Int,
        nextSeason: Int?,
        nextEpisode: Int,
    ): String? {
        if (filename.isBlank()) return null

        // Try each pattern from most specific to least specific.
        // Return on first match to avoid replacing unrelated numbers.
        for (pattern in patterns) {
            val result = pattern.replace(
                filename, currentSeason, currentEpisode, nextSeason, nextEpisode,
            )
            if (result != null) return result
        }
        return null
    }

    /**
     * Checks whether a candidate filename matches the expected next filename.
     * Comparison is case-insensitive.
     */
    fun matches(candidateFilename: String?, expectedFilename: String?): Boolean {
        if (candidateFilename.isNullOrBlank() || expectedFilename.isNullOrBlank()) return false
        return candidateFilename.equals(expectedFilename, ignoreCase = true)
    }

    private interface EpisodePattern {
        fun replace(
            filename: String,
            currentSeason: Int?,
            currentEpisode: Int,
            nextSeason: Int?,
            nextEpisode: Int,
        ): String?
    }

    private val sXeY = object : EpisodePattern {
        // Matches S, optional space, season digits, E, optional space, episode digits
        private val regex = Regex(
            """(?i)(S)\s*(\d{1,3})\s*(E)\s*(\d{1,4})""",
        )

        override fun replace(
            filename: String,
            currentSeason: Int?,
            currentEpisode: Int,
            nextSeason: Int?,
            nextEpisode: Int,
        ): String? {
            if (currentSeason == null) return null
            val match = regex.find(filename) ?: return null
            val matchedSeason = match.groupValues[2].toIntOrNull() ?: return null
            val matchedEpisode = match.groupValues[4].toIntOrNull() ?: return null
            if (matchedSeason != currentSeason || matchedEpisode != currentEpisode) return null

            // Preserve the original zero-padding width
            val seasonWidth = match.groupValues[2].length
            val episodeWidth = match.groupValues[4].length
            val nextSeasonStr = (nextSeason ?: currentSeason).toString().padStart(seasonWidth, '0')
            val nextEpisodeStr = nextEpisode.toString().padStart(episodeWidth, '0')

            // Reconstruct with same S/E casing and spacing
            val replacement = "${match.groupValues[1]}${nextSeasonStr}${match.groupValues[3]}${nextEpisodeStr}"
            return filename.replaceRange(match.range, replacement)
        }
    }

    private val seasonXepisode = object : EpisodePattern {
        private val regex = Regex("""(?<!\d)(\d{1,2})[xX](\d{1,4})""")

        override fun replace(
            filename: String,
            currentSeason: Int?,
            currentEpisode: Int,
            nextSeason: Int?,
            nextEpisode: Int,
        ): String? {
            if (currentSeason == null) return null
            val match = regex.find(filename) ?: return null
            val matchedSeason = match.groupValues[1].toIntOrNull() ?: return null
            val matchedEpisode = match.groupValues[2].toIntOrNull() ?: return null
            if (matchedSeason != currentSeason || matchedEpisode != currentEpisode) return null

            val seasonWidth = match.groupValues[1].length
            val episodeWidth = match.groupValues[2].length
            val sep = filename[match.range.first + match.groupValues[1].length]
            val replacement = "${(nextSeason ?: currentSeason).toString().padStart(seasonWidth, '0')}${sep}${nextEpisode.toString().padStart(episodeWidth, '0')}"
            return filename.replaceRange(match.range, replacement)
        }
    }

    private val episodeOnly = object : EpisodePattern {
        private val regex = Regex("""(?i)\b(E[Pp]?)[.\s]?(\d{1,4})\b""")

        override fun replace(
            filename: String,
            currentSeason: Int?,
            currentEpisode: Int,
            nextSeason: Int?,
            nextEpisode: Int,
        ): String? {
            // Fork deviation (review r1 P3): this pattern carries no season, so a season change
            // (S1E10 → S2E1) must not rewrite E10 → E01 and match season 1's first episode.
            if (nextSeason != null && currentSeason != null && nextSeason != currentSeason) return null
            val match = regex.find(filename) ?: return null
            val matchedEpisode = match.groupValues[2].toIntOrNull() ?: return null
            if (matchedEpisode != currentEpisode) return null

            val episodeWidth = match.groupValues[2].length
            val prefix = match.groupValues[1]
            val separator = filename.substring(
                match.range.first + prefix.length,
                match.range.first + prefix.length + (match.value.length - prefix.length - match.groupValues[2].length),
            )
            val replacement = "$prefix$separator${nextEpisode.toString().padStart(episodeWidth, '0')}"
            return filename.replaceRange(match.range, replacement)
        }
    }

    fun extractSeasonEpisode(filename: String): Pair<Int?, Int>? {
        if (filename.isBlank()) return null
        // S01E03 pattern
        Regex("""(?i)S\s*(\d{1,3})\s*E\s*(\d{1,4})""").find(filename)?.let { match ->
            val season = match.groupValues[1].toIntOrNull()
            val episode = match.groupValues[2].toIntOrNull() ?: return null
            return season to episode
        }
        // 01x03 pattern
        Regex("""(?<!\d)(\d{1,2})[xX](\d{1,4})""").find(filename)?.let { match ->
            val season = match.groupValues[1].toIntOrNull()
            val episode = match.groupValues[2].toIntOrNull() ?: return null
            return season to episode
        }
        // E03, EP03, EP.03 pattern (no season)
        Regex("""(?i)\bE[Pp]?[.\s]?(\d{1,4})\b""").find(filename)?.let { match ->
            val episode = match.groupValues[1].toIntOrNull() ?: return null
            return null to episode
        }
        return null
    }

    private val patterns = listOf(sXeY, seasonXepisode, episodeOnly)

    // ---- Fork additions (tvOS Up Next engine) ----

    /**
     * The filename the next episode's stream should carry when it is the same release as the
     * playing one. Upstream 953938c72 (`playNextEpisode`'s `tryBingeGroupOnly`/`tryFilenameOnly`):
     * `buildNextFilename(current.orEmpty(), currentSeason, currentEpisode ?: 0, nextSeason,
     * nextEpisode ?: 0) ?: current?.takeIf { it.isNotBlank() }`. The fallback (no episode token,
     * or the token did not match the playing episode's numbers) is the playing filename itself,
     * which only matches a next-episode stream named identically (a pack an add-on names the same
     * for every episode). Null when the playing stream declared no filename.
     */
    fun expectedNextFilename(
        currentFilename: String?,
        currentSeason: Int?,
        currentEpisode: Int?,
        nextSeason: Int?,
        nextEpisode: Int?,
    ): String? {
        val current = currentFilename?.takeIf { it.isNotBlank() } ?: return null
        buildNextFilename(
            filename = current,
            currentSeason = currentSeason,
            currentEpisode = currentEpisode ?: 0,
            nextSeason = nextSeason,
            nextEpisode = nextEpisode ?: 0,
        )?.let { return it }
        // Fork deviation (review r1 P3): the same-name fallback only when the playing file carries
        // no episode token at all (a pack named the same for every episode). A token that did not
        // match (absolute anime numbering, a season change on an episode-only name) would make the
        // fallback match the CURRENT episode's file again.
        return if (extractSeasonEpisode(current) == null) current else null
    }

    /**
     * The first stream, in list order, whose `behaviorHints.filename` equals [expectedFilename]
     * (case-insensitive) and, when [bingeGroup] is non-blank, whose `behaviorHints.bingeGroup` is
     * exactly that group. Null [bingeGroup] = any group (upstream's `tryFilenameOnly`).
     *
     * Deliberately NOT scoped by the auto-play source / add-on / plugin filters: upstream
     * d293973bd ("binge group reuse should not be limited by autoplay source/addon selection
     * filters") and 953938c72 search every stream for the same release. Playability is the
     * caller's job: pass only streams it may auto-select (tvOS: `NextEpisodeEngine.allStreams`,
     * direct links and debrid candidates, rejected links already removed).
     */
    fun findMatch(
        streams: List<StreamItem>,
        expectedFilename: String?,
        bingeGroup: String?,
    ): StreamItem? {
        if (expectedFilename.isNullOrBlank()) return null
        val group = bingeGroup?.trim()?.takeIf { it.isNotEmpty() }
        return streams.firstOrNull { stream ->
            (group == null || stream.behaviorHints.bingeGroup == group) &&
                matches(stream.behaviorHints.filename, expectedFilename)
        }
    }

    /**
     * Upstream d2cc0fb8a's second step: the first stream, in list order, in the same non-blank
     * [bingeGroup] whose torrent info hash ([StreamItem.p2pInfoHash]: top-level, `clientResolve`,
     * magnet or `torrent://`) equals [infoHash] (case-insensitive). Covers season packs, where one
     * torrent serves every episode and the add-on gives no usable filename. Same candidate rules
     * as [findMatch]. Null for a blank group or a null / blank hash.
     */
    fun findInfoHashMatch(
        streams: List<StreamItem>,
        infoHash: String?,
        bingeGroup: String?,
    ): StreamItem? {
        val hash = infoHash?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val group = bingeGroup?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return streams.firstOrNull { stream ->
            stream.behaviorHints.bingeGroup == group &&
                stream.p2pInfoHash.equals(hash, ignoreCase = true)
        }
    }
}
