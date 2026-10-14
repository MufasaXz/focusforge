package dev.focusforge.focusforge.widgets

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF

/** Bars are decorative; totals, weekday labels and spoken values stay native. */
internal object WeeklyWidgetRenderer {
    fun render(widthPx: Int, heightPx: Int, summary: WidgetSessionSummary, accent: Int, secondary: Int): Bitmap {
        val width = widthPx.coerceIn(140, 960)
        val height = heightPx.coerceIn(24, 640)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val column = width / 7f
        val barWidth = column * .38f
        val floor = height - 3f
        val top = 4f
        val available = (floor - top - 5f).coerceAtLeast(1f)
        val maximum = summary.dayMinutes.maxOrNull()?.coerceAtLeast(1) ?: 1
        for (day in 0..6) {
            val centre = (day + .5f) * column
            if (day == summary.todayIndex) {
                paint.color = withAlpha(accent, 24)
                canvas.drawRoundRect(RectF(centre - column * .4f, 0f, centre + column * .4f, height.toFloat()), column * .2f, column * .2f, paint)
            }
            val value = summary.dayMinutes[day]
            paint.color = when {
                day > summary.todayIndex -> withAlpha(secondary, 55)
                day == summary.todayIndex -> accent
                else -> withAlpha(accent, 160)
            }
            val barHeight = if (value > 0) (value.toFloat() / maximum * available).coerceAtLeast(4f) else 3f
            canvas.drawRoundRect(RectF(centre - barWidth / 2, floor - barHeight, centre + barWidth / 2, floor), barWidth / 2, barWidth / 2, paint)
        }
        return bitmap
    }

    private fun withAlpha(color: Int, alpha: Int) = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
