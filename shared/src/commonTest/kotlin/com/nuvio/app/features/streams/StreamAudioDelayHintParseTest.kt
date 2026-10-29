package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StreamAudioDelayHintParseTest {
    private fun parse(hint: String): Int? {
        val payload = """{"streams":[{"url":"https://example.com/v.mkv","behaviorHints":{$hint}}]}"""
        return StreamParser.parse(payload, addonName = "A", addonId = "a").single().behaviorHints.audioDelayMs
    }

    @Test
    fun parsesNumber() = assertEquals(-2500, parse(""""audioDelayMs": -2500"""))

    @Test
    fun parsesNumericString() = assertEquals(30000, parse(""""audioDelayMs": "30000""""))

    @Test
    fun clampsToSixtySeconds() {
        assertEquals(60_000, parse(""""audioDelayMs": 900000"""))
        assertEquals(-60_000, parse(""""audioDelayMs": -900000"""))
    }

    @Test
    fun absentIsNull() = assertNull(parse(""""filename": "x.mkv""""))

    @Test
    fun nonNumericIsNull() = assertNull(parse(""""audioDelayMs": "soon""""))
}
