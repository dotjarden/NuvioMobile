package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * OpenSubtitles Spanish-EU aliases (upstream NuvioTV 2a54e8cbe) and Serbo-Croatian
 * "hbs-" labels (upstream NuvioTV d34a5025d).
 */
class PlayerSubtitleMatchingAliasTest {

    @Test
    fun spanishEuCodesNormalizeToSpanish() {
        assertEquals("es", SubtitleLanguageMatching.normalizeLanguageCode("spn"))
        assertEquals("es", SubtitleLanguageMatching.normalizeLanguageCode("sp"))
        assertEquals("es", SubtitleLanguageMatching.normalizeLanguageCode("ESP"))
        assertTrue(SubtitleLanguageMatching.matchesLanguageCode("spn", "es"))
    }

    @Test
    fun latinAmericanCodeStaysLatinAmerican() {
        assertEquals("es-419", SubtitleLanguageMatching.normalizeLanguageCode("spl"))
    }

    @Test
    fun hbsLabelsResolveToTheirOwnLanguage() {
        assertEquals("sr", SubtitleLanguageMatching.normalizeLanguageCode("hbs-srp"))
        assertEquals("hr", SubtitleLanguageMatching.normalizeLanguageCode("hbs-hrv"))
        assertEquals("bs", SubtitleLanguageMatching.normalizeLanguageCode("hbs_bos"))
    }

    @Test
    fun bareHbsIsLeftAlone() {
        assertEquals("hbs", SubtitleLanguageMatching.normalizeLanguageCode("hbs"))
    }

    @Test
    fun audioPreferenceAliasesCoverSpanishEuCodes() {
        assertEquals("es", normalizeLanguageCode("spn"))
        assertEquals("es", normalizeLanguageCode("esp"))
    }
}
