package dev.focusforge.focusforge.widgets

import kotlin.math.min

/** Each layout spends space on the primary value before auxiliary labels. */
internal data class WeeklyWidgetLayout(
    val paddingDp: Int,
    val headlineSp: Float,
    val summarySp: Float,
    val chartHeightDp: Float,
    val showTitle: Boolean,
    val showCaption: Boolean,
    val shortSummary: Boolean,
    val contentHeightDp: Float,
) {
    companion object {
        fun forWidget(widthDp: Int, heightDp: Int, fontScale: Float, headline: String): WeeklyWidgetLayout {
            val scale = fontScale.coerceAtLeast(1f)
            val padding = if (widthDp < 220 || heightDp < 220 || scale > 1.3f) 12 else 18
            val width = (widthDp - 2 * padding).coerceAtLeast(1).toFloat()
            val height = (heightDp - 2 * padding).coerceAtLeast(1).toFloat()
            val shortSummary = width / scale < 180
            val headlineSp = min(30f, min(height * .25f / (1.2f * scale), width / (headline.length.coerceAtLeast(1) * .62f * scale)))
            val summarySp = min(12f, width / ((if (shortSummary) 10 else 13) * .62f * scale))
            val headlineHeight = headlineSp * scale * 1.2f
            val summaryHeight = summarySp * scale * 1.25f
            val showTitle = height / scale >= 120
            val showCaption = height / scale >= 200
            val reserved = headlineHeight + summaryHeight + 10f * scale * 1.25f + 12f +
                (if (showTitle) 12f * scale + 6f else 0f) +
                (if (showCaption) 12f * scale + 6f else 0f)
            val chartHeight = (height - reserved).coerceAtLeast(20f)
            return WeeklyWidgetLayout(padding, headlineSp, summarySp, chartHeight, showTitle, showCaption, shortSummary, reserved + chartHeight)
        }
    }
}

internal data class StudyWidgetLayout(
    val paddingDp: Int,
    val countdownSp: Float,
    val subjectSp: Float,
    val showTitle: Boolean,
    val showSubject: Boolean,
    val showProgress: Boolean,
    val showCaption: Boolean,
    val contentHeightDp: Float,
) {
    companion object {
        fun forWidget(widthDp: Int, heightDp: Int, fontScale: Float, digits: Int): StudyWidgetLayout {
            val scale = fontScale.coerceAtLeast(1f)
            val padding = if (widthDp < 220 || heightDp < 220 || scale > 1.3f) 12 else 18
            val width = (widthDp - 2 * padding).coerceAtLeast(1).toFloat()
            val height = (heightDp - 2 * padding).coerceAtLeast(1).toFloat()
            val timeSp = min(38f, min(width / (digits.coerceAtLeast(5) * .62f * scale), height * .46f / scale))
            val subjectSp = if (width / scale < 120) 12f else 18f
            val showTitle = height / scale >= 110
            val showSubject = height / scale >= 70
            val showProgress = height / scale >= 125
            val showCaption = height / scale >= 160
            val content = timeSp * scale * 1.25f +
                (if (showTitle) 13f * scale + 6f else 0f) +
                (if (showSubject) subjectSp * scale * 1.25f + 6f else 0f) +
                (if (showProgress) 16f * scale + 6f else 0f) +
                (if (showCaption) 12f * scale + 3f else 0f)
            return StudyWidgetLayout(padding, timeSp, subjectSp, showTitle, showSubject, showProgress, showCaption, content)
        }
    }
}
