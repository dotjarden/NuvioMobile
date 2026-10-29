package com.nuvio.app.features.player

const val STREAM_AUDIO_DELAY_MAX_MS = 60_000

/// [savedMs]: the per-episode value the viewer saved. [streamMs]: the add-on's
/// `behaviorHints.audioDelayMs` (null = none). [sessionAdjustMs]: the viewer's tweak on top of a hint,
/// never saved.
data class AudioDelayParts(val savedMs: Int, val streamMs: Int?, val sessionAdjustMs: Int = 0)

object StreamAudioDelay {
    private fun clampStream(ms: Int) = ms.coerceIn(-STREAM_AUDIO_DELAY_MAX_MS, STREAM_AUDIO_DELAY_MAX_MS)
    private fun clampSaved(ms: Int) = ms.coerceIn(AUDIO_DELAY_MIN_MS, AUDIO_DELAY_MAX_MS)

    /// Hint active: clamp(stream + session, +-60 s). Else clamp(saved, +-10 s).
    fun totalMs(parts: AudioDelayParts): Int {
        val stream = parts.streamMs
        return if (stream != null) clampStream(stream + parts.sessionAdjustMs) else clampSaved(parts.savedMs)
    }

    /// The viewer set a new total. Hint active: sessionAdjust = total - stream (never saved).
    /// Else saved = clamp(total, +-10 s).
    fun applyUserTotal(parts: AudioDelayParts, newTotalMs: Int): AudioDelayParts {
        val stream = parts.streamMs
        return if (stream != null) {
            parts.copy(sessionAdjustMs = clampStream(newTotalMs) - stream)
        } else {
            parts.copy(savedMs = clampSaved(newTotalMs))
        }
    }

    /// What to persist per episode: the saved value when no hint is active, else null.
    fun persistableMs(parts: AudioDelayParts): Int? =
        if (parts.streamMs == null) clampSaved(parts.savedMs) else null

    /// The Audio Delay row's limit: 60 000 with a hint, else 10 000.
    fun uiLimitMs(parts: AudioDelayParts): Int =
        if (parts.streamMs != null) STREAM_AUDIO_DELAY_MAX_MS else AUDIO_DELAY_MAX_MS
}
