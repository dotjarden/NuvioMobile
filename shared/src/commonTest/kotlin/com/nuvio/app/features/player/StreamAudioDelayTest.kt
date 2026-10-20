package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StreamAudioDelayTest {
    @Test
    fun noHintUsesSavedValue() {
        assertEquals(1500, StreamAudioDelay.totalMs(AudioDelayParts(savedMs = 1500, streamMs = null)))
    }

    @Test
    fun hintBecomesTheBase() {
        // A saved value is ignored while a hint is active.
        assertEquals(30_000, StreamAudioDelay.totalMs(AudioDelayParts(savedMs = 1500, streamMs = 30_000)))
    }

    @Test
    fun sessionTweakAddsToHint() {
        assertEquals(30_250, StreamAudioDelay.totalMs(AudioDelayParts(0, 30_000, 250)))
    }

    @Test
    fun totalClampsToSixtySeconds() {
        assertEquals(60_000, StreamAudioDelay.totalMs(AudioDelayParts(0, 59_000, 5_000)))
        assertEquals(-60_000, StreamAudioDelay.totalMs(AudioDelayParts(0, -59_000, -5_000)))
    }

    @Test
    fun savedClampsToTenSeconds() {
        assertEquals(10_000, StreamAudioDelay.totalMs(AudioDelayParts(25_000, null)))
        assertEquals(-10_000, StreamAudioDelay.totalMs(AudioDelayParts(-25_000, null)))
    }

    @Test
    fun userTotalWithHintChangesOnlySession() {
        val next = StreamAudioDelay.applyUserTotal(AudioDelayParts(500, 30_000), 30_750)
        assertEquals(750, next.sessionAdjustMs)
        assertEquals(500, next.savedMs)
        assertEquals(30_750, StreamAudioDelay.totalMs(next))
    }

    @Test
    fun userTotalWithoutHintChangesSaved() {
        val next = StreamAudioDelay.applyUserTotal(AudioDelayParts(0, null), 2_000)
        assertEquals(2_000, next.savedMs)
        assertEquals(0, next.sessionAdjustMs)
        assertEquals(10_000, StreamAudioDelay.applyUserTotal(next, 40_000).savedMs)
    }

    @Test
    fun persistableOnlyWithoutHint() {
        assertEquals(1_000, StreamAudioDelay.persistableMs(AudioDelayParts(1_000, null)))
        assertNull(StreamAudioDelay.persistableMs(AudioDelayParts(1_000, 30_000, 100)))
    }

    @Test
    fun uiLimitFollowsHint() {
        assertEquals(60_000, StreamAudioDelay.uiLimitMs(AudioDelayParts(0, 30_000)))
        assertEquals(10_000, StreamAudioDelay.uiLimitMs(AudioDelayParts(0, null)))
    }

    @Test
    fun newStreamDropsSessionTweak() {
        val tweaked = AudioDelayParts(0, 30_000, 750)
        val fresh = AudioDelayParts(savedMs = 0, streamMs = 12_000)
        assertEquals(30_750, StreamAudioDelay.totalMs(tweaked))
        assertEquals(12_000, StreamAudioDelay.totalMs(fresh))
    }
}
