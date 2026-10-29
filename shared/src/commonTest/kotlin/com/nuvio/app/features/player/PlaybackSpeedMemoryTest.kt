package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PlaybackSpeedMemoryTest {
    @Test
    fun encodeRounds() {
        assertEquals(125, PlaybackSpeedMemory.encode(1.25))
        assertEquals(75, PlaybackSpeedMemory.encode(0.75))
        assertEquals(100, PlaybackSpeedMemory.encode(1.0))
        assertEquals(133, PlaybackSpeedMemory.encode(1.3333))
    }

    @Test
    fun decodeRoundTrips() {
        for (hundredths in 50..200 step 25) {
            val speed = hundredths / 100.0
            assertEquals(speed, PlaybackSpeedMemory.decode(PlaybackSpeedMemory.encode(speed)))
        }
    }

    @Test
    fun decodeRejectsOutOfRange() {
        assertNull(PlaybackSpeedMemory.decode(49))
        assertNull(PlaybackSpeedMemory.decode(201))
        assertNull(PlaybackSpeedMemory.decode(0))
        assertNull(PlaybackSpeedMemory.decode(-100))
    }
}
