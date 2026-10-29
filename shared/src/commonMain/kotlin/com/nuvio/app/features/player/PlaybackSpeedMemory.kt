package com.nuvio.app.features.player

import kotlin.math.roundToInt

/// Per-show playback speed is stored as an Int in hundredths (1.25 -> 125).
object PlaybackSpeedMemory {
    const val MIN_STORED = 50
    const val MAX_STORED = 200

    fun encode(speed: Double): Int = (speed * 100).roundToInt()

    /// null when [stored] is outside 50..200 (0.5x..2.0x).
    fun decode(stored: Int): Double? =
        if (stored in MIN_STORED..MAX_STORED) stored / 100.0 else null
}
