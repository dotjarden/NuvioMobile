package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SubtitleSyncLineTest {
    private fun cue(start: Long) = SubtitleSyncCue(startTimeMs = start, text = "c$start")

    @Test
    fun delayIsCapturedMinusCueMinusReaction() {
        assertEquals(4_700, SubtitleSyncLine.delayMs(65_000, 60_000))
    }

    @Test
    fun negativeDelayWhenSubtitlesLate() {
        assertEquals(-5_300, SubtitleSyncLine.delayMs(10_000, 15_000))
    }

    @Test
    fun delayClampsToSixtySeconds() {
        assertEquals(60_000, SubtitleSyncLine.delayMs(200_000, 0))
        assertEquals(-60_000, SubtitleSyncLine.delayMs(0, 200_000))
    }

    @Test
    fun windowUsesShownTimeNotPosition() {
        val cues = listOf(cue(64_000), cue(66_000), cue(105_000), cue(106_000))
        val result = SubtitleSyncLine.window(cues, 100_000, 5_000).map { it.startTimeMs }
        assertEquals(listOf(66_000L, 105_000L), result)
    }

    @Test
    fun windowCapsAtThirtyKeepingTheLatest() {
        val cues = (0 until 50).map { cue(80_000L + it * 200L) }
        val result = SubtitleSyncLine.window(cues, 90_000, 0)
        assertEquals(30, result.size)
        assertEquals(cues.last().startTimeMs, result.last().startTimeMs)
        assertTrue(result.first().startTimeMs < result.last().startTimeMs)
    }

    @Test
    fun anchorIsLastCueAtOrBeforeShownTime() {
        val windowed = listOf(cue(1_000), cue(2_000), cue(3_000))
        assertEquals(1, SubtitleSyncLine.anchorIndex(windowed, 2_500, 0))
        assertEquals(1, SubtitleSyncLine.anchorIndex(windowed, 2_000, 0))
    }

    @Test
    fun anchorIsZeroWhenAllCuesAreLater() {
        val windowed = listOf(cue(5_000), cue(6_000))
        assertEquals(0, SubtitleSyncLine.anchorIndex(windowed, 1_000, 0))
    }

    @Test
    fun anchorIsNullForEmptyWindow() {
        assertNull(SubtitleSyncLine.anchorIndex(emptyList(), 1_000, 0))
    }
}
