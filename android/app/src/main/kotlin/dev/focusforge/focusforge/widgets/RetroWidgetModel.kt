package dev.focusforge.focusforge.widgets

import org.json.JSONObject
import kotlin.math.min

/** Uses the saved segment deadline, just like the focus screen. */
internal data class RetroWidgetState(
    val remainingMs: Long,
    val running: Boolean,
    val progress: Double,
) {
    companion object {
        fun from(timer: JSONObject, nowMs: Long): RetroWidgetState {
            val target = timer.optLong("targetEnd", 0)
            val requestedRunning = timer.optBoolean("running")
            val running = requestedRunning && target > nowMs
            val remaining = when {
                running -> target - nowMs
                requestedRunning -> 0L
                else -> timer.optLong("remainingMs", 25 * 60_000L).coerceAtLeast(0L)
            }
            val planned = timer.optLong("plannedMs", timer.optLong("remainingMs", remaining))
                .coerceAtLeast(remaining).coerceAtLeast(1L)
            return RetroWidgetState(
                remaining, running, (1.0 - remaining.toDouble() / planned).coerceIn(0.0, 1.0),
            )
        }
    }
}

/** Text fits the dial's centre, after accounting for visible native labels. */
internal data class RetroWidgetLayout(
    val paddingDp: Int,
    val dialDp: Float,
    val fontScale: Float,
    val showTitle: Boolean,
    val showSubject: Boolean,
    val showProgress: Boolean,
    val showCaption: Boolean,
) {
    fun countdownSp(remainingMs: Long): Float {
        val hours = remainingMs.coerceAtLeast(0L) / 3_600_000L
        val characters = if (hours > 0) hours.toString().length + 6 else 5
        return min(dialDp * 0.17f / fontScale, dialDp * 0.58f / (characters * 0.59f * fontScale))
    }

    companion object {
        fun forWidget(widthDp: Int, heightDp: Int, fontScale: Float): RetroWidgetLayout {
            val scale = fontScale.coerceAtLeast(1f)
            val padding = if (widthDp < 190 || heightDp < 190 || scale > 1.3f) 12 else 18
            val scaledHeight = heightDp / scale
            val showTitle = scaledHeight >= 100
            val showSubject = scaledHeight >= 200
            val showProgress = scaledHeight >= 220
            val showCaption = scaledHeight >= 280
            // Includes font padding and each label's layout spacing. The dial
            // also gets an 8dp breathing space above/below the image.
            val reserved = (if (showTitle) 15f * scale else 0f) +
                (if (showSubject) 20f * scale + 6f else 0f) +
                (if (showProgress) 20f * scale else 0f) +
                (if (showCaption) 14f * scale + 3f else 0f) + 8f
            val availableWidth = (widthDp - 2 * padding).coerceAtLeast(1).toFloat()
            val availableHeight = (heightDp - 2 * padding - reserved).coerceAtLeast(1f)
            return RetroWidgetLayout(
                padding, min(availableWidth, availableHeight), scale,
                showTitle, showSubject, showProgress, showCaption,
            )
        }
    }
}
