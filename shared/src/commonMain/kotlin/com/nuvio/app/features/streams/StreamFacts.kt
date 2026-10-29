package com.nuvio.app.features.streams

import com.nuvio.app.features.debrid.DebridStreamAudioChannel
import com.nuvio.app.features.debrid.DebridStreamAudioTag
import com.nuvio.app.features.debrid.DebridStreamEncode
import com.nuvio.app.features.debrid.DebridStreamMetadata
import com.nuvio.app.features.debrid.DebridStreamPreferences
import com.nuvio.app.features.debrid.DebridStreamQuality
import com.nuvio.app.features.debrid.DebridStreamResolution
import com.nuvio.app.features.debrid.DebridStreamVisualTag

/**
 * Stream picker A, P0.4: the structured facts Direction B (best source + quality tiers) will read
 * for one stream. Every field is nullable: a fact the add-on did not state stays `null` rather
 * than guessing. Nothing in Direction A renders this; it exists so B can sit on top of A without
 * touching the row models.
 *
 * Fields today come from the same parser the Sources filters and Auto-Play Best Source use
 * (`DebridStreamMetadata.facts`, over name / title / description / filename / resolve data), so a
 * stream the filters read as 2160p HDR is 2160p HDR here too. Languages additionally read the
 * flag emoji that Torrentio and AIOStreams print, which the filter parser ignores.
 */
data class StreamFacts(
    /** Vertical resolution in lines (2160, 1080, 720 …); null when no resolution tag was found. */
    val resolution: Int? = null,
    /** Dynamic range as a short label: "DV", "HDR", "HDR10", "HDR10+", "HLG", or "DV HDR10" for both. */
    val hdr: String? = null,
    /** Source type: "BluRay REMUX", "BluRay", "WEB-DL", "WEBRip", … */
    val sourceType: String? = null,
    /** Video encode: "HEVC", "AVC", "AV1", … */
    val codec: String? = null,
    /** Audio formats and layout, space separated: "TrueHD Atmos 7.1", "DD+ 5.1", "AAC". */
    val audio: String? = null,
    /** File size in bytes from the add-on's `behaviorHints.videoSize` or the resolved file. */
    val sizeBytes: Long? = null,
    /**
     * `true` for a debrid link the add-on reports as cached / direct, `false` for a debrid
     * candidate that is not (yet) cached, `null` when the stream is not a debrid candidate at all
     * (plain HTTP, YouTube, external). Same notion as [StreamQualityRank.Key.cached].
     */
    val cached: Boolean? = null,
    /** ISO 639-1 codes in the order found, e.g. ["en", "fr"]. Empty when none was stated. */
    val languages: List<String> = emptyList(),
)

object StreamFactsParser {

    private val defaultPreferences = DebridStreamPreferences()

    // Regional-indicator pairs → ISO 639-1. Torrentio prints "🇬🇧 / 🇫🇷", AIOStreams
    // "Languages: 🇬🇧,🇪🇸,🇫🇷". Only flags whose language is unambiguous are mapped.
    private val flagLanguages: Map<String, String> = mapOf(
        "GB" to "en", "US" to "en", "AU" to "en", "CA" to "en", "NZ" to "en",
        "FR" to "fr", "ES" to "es", "MX" to "es", "DE" to "de", "AT" to "de",
        "IT" to "it", "PT" to "pt", "BR" to "pt", "RU" to "ru", "JP" to "ja",
        "KR" to "ko", "CN" to "zh", "TW" to "zh", "NL" to "nl", "SE" to "sv",
        "NO" to "no", "DK" to "da", "FI" to "fi", "PL" to "pl", "CZ" to "cs",
        "HU" to "hu", "GR" to "el", "TR" to "tr", "IN" to "hi", "SA" to "ar",
        "IL" to "he", "TH" to "th", "VN" to "vi", "ID" to "id", "UA" to "uk",
        "RO" to "ro", "BG" to "bg", "HR" to "hr", "RS" to "sr", "SK" to "sk",
    )

    fun parse(stream: StreamItem): StreamFacts {
        val facts = DebridStreamMetadata.facts(stream, defaultPreferences)
        val isDebridCandidate = stream.isAddonDebridCandidate
        val isCachedDebridLink = isDebridCandidate &&
            (stream.isDirectDebridStream || stream.isCachedDebridTorrentStream)
        val parsedLanguages = facts.languages.map { it.code }
        val flagCodes = flagLanguageCodes(stream)
        return StreamFacts(
            resolution = facts.resolution.takeIf { it != DebridStreamResolution.UNKNOWN }?.value,
            hdr = hdrLabel(facts.visualTags),
            sourceType = facts.quality.takeIf { it != DebridStreamQuality.UNKNOWN }?.label,
            codec = facts.encode.takeIf { it != DebridStreamEncode.UNKNOWN }?.label,
            audio = audioLabel(facts.audioTags, facts.audioChannels),
            sizeBytes = facts.size,
            cached = if (isDebridCandidate) isCachedDebridLink else null,
            languages = (parsedLanguages + flagCodes).distinct(),
        )
    }

    private fun hdrLabel(tags: List<DebridStreamVisualTag>): String? {
        val hasDv = DebridStreamVisualTag.DV in tags
        val hdr = when {
            DebridStreamVisualTag.HDR10_PLUS in tags -> "HDR10+"
            DebridStreamVisualTag.HDR10 in tags -> "HDR10"
            DebridStreamVisualTag.HLG in tags -> "HLG"
            DebridStreamVisualTag.HDR in tags -> "HDR"
            else -> null
        }
        return listOfNotNull("DV".takeIf { hasDv }, hdr).joinToString(" ").ifEmpty { null }
    }

    private fun audioLabel(
        tags: List<DebridStreamAudioTag>,
        channels: List<DebridStreamAudioChannel>,
    ): String? {
        val known = tags.filter { it != DebridStreamAudioTag.UNKNOWN }
        // "Dolby Digital Plus" matches both DD+ and the plain DD token in the filter parser; one
        // label is enough here.
        var formats = if (DebridStreamAudioTag.DD_PLUS in known) known - DebridStreamAudioTag.DD else known
        // The DTS token also matches inside "DTS-HD" / "DTS-HD MA", so keep only the most specific.
        if (DebridStreamAudioTag.DTS_HD_MA in formats) {
            formats = formats - DebridStreamAudioTag.DTS_HD - DebridStreamAudioTag.DTS
        }
        if (DebridStreamAudioTag.DTS_HD in formats ||
            DebridStreamAudioTag.DTS_X in formats ||
            DebridStreamAudioTag.DTS_ES in formats
        ) {
            formats = formats - DebridStreamAudioTag.DTS
        }
        val layout = channels.filter { it != DebridStreamAudioChannel.UNKNOWN }
        val parts = formats.map { it.label } + layout.map { it.label }
        return parts.joinToString(" ").ifEmpty { null }
    }

    private fun flagLanguageCodes(stream: StreamItem): List<String> {
        val text = listOfNotNull(stream.name, stream.title, stream.description).joinToString("\n")
        val codes = mutableListOf<String>()
        val letters = StringBuilder()
        var index = 0
        while (index < text.length) {
            val letter = regionalIndicatorLetterAt(text, index)
            if (letter == null) {
                letters.clear()
                index += 1
                continue
            }
            letters.append(letter)
            index += 2
            if (letters.length == 2) {
                flagLanguages[letters.toString()]?.let(codes::add)
                letters.clear()
            }
        }
        return codes.distinct()
    }

    /**
     * A regional indicator symbol (U+1F1E6..U+1F1FF, the halves of a flag emoji) as its letter,
     * read as a surrogate pair so it behaves the same on the JVM and Kotlin/Native.
     */
    private fun regionalIndicatorLetterAt(text: String, index: Int): Char? {
        if (index + 1 >= text.length) return null
        val high = text[index]
        val low = text[index + 1]
        if (!high.isHighSurrogate() || !low.isLowSurrogate()) return null
        val codePoint = ((high.code - 0xD800) shl 10) + (low.code - 0xDC00) + 0x10000
        return if (codePoint in 0x1F1E6..0x1F1FF) 'A' + (codePoint - 0x1F1E6) else null
    }
}
