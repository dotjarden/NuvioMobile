package com.nuvio.app.features.player

/**
 * Sync Line (P5 B19): pick the subtitle line you just heard and derive the subtitle delay from it.
 * Mirrors composeApp's PlayerScreenRuntimeSubtitleActions auto-sync maths so tvOS shares one tested copy.
 * Cue times are the RAW file times (the parser reads the unshifted file).
 */
object SubtitleSyncLine {
    const val WINDOW_BEFORE_MS = 30_000L
    const val WINDOW_AFTER_MS = 10_000L
    const val MAX_ROWS = 30

    /** The delay that puts [cueStartMs] at [capturedPositionMs] minus the reaction time. */
    fun delayMs(capturedPositionMs: Long, cueStartMs: Long): Int =
        (capturedPositionMs - cueStartMs - SUBTITLE_AUTO_SYNC_REACTION_COMPENSATION_MS)
            .coerceIn(SUBTITLE_DELAY_MIN_MS.toLong(), SUBTITLE_DELAY_MAX_MS.toLong())
            .toInt()

    /** The raw cue time the subtitles are showing now: position minus the current delay. */
    fun shownCueTimeMs(capturedPositionMs: Long, currentDelayMs: Int): Long =
        capturedPositionMs - currentDelayMs

    /** Cues sorted by start, whose start is within [shown - 30 s, shown + 10 s], at most 30 (the last 30 when more). */
    fun window(
        cues: List<SubtitleSyncCue>,
        capturedPositionMs: Long,
        currentDelayMs: Int,
    ): List<SubtitleSyncCue> {
        val shown = shownCueTimeMs(capturedPositionMs, currentDelayMs)
        val inWindow = cues
            .filter { it.startTimeMs >= shown - WINDOW_BEFORE_MS && it.startTimeMs <= shown + WINDOW_AFTER_MS }
            .sortedBy { it.startTimeMs }
        return if (inWindow.size > MAX_ROWS) inWindow.takeLast(MAX_ROWS) else inWindow
    }

    /** Index in [windowed] of the last cue starting at or before the shown time; 0 when none; null when empty. */
    fun anchorIndex(
        windowed: List<SubtitleSyncCue>,
        capturedPositionMs: Long,
        currentDelayMs: Int,
    ): Int? {
        if (windowed.isEmpty()) return null
        val shown = shownCueTimeMs(capturedPositionMs, currentDelayMs)
        val idx = windowed.indexOfLast { it.startTimeMs <= shown }
        return if (idx < 0) 0 else idx
    }
}
