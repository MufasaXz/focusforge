package dev.focusforge.focusforge.widgets

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** FocusForge's own retro face, drawn once when the launcher refreshes. */
internal object RetroWidgetRenderer {
    fun render(
        diameterPx: Int,
        progress: Double,
        dark: Boolean,
        amoled: Boolean,
        accent: Int,
        marks: Int,
        labelTypeface: Typeface,
    ): Bitmap {
        val size = diameterPx.coerceIn(144, 640)
        val s = size.toFloat()
        val centre = s / 2f
        val radius = s * 0.47f
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val surface = Color.parseColor(if (dark) { if (amoled) "#0C0C0C" else "#2A2D31" } else "#DCD0B4")
        paint.color = withAlpha(Color.BLACK, if (dark) 0.25f else 0.10f)
        paint.setShadowLayer(s * 0.024f, 0f, s * 0.016f, paint.color)
        canvas.drawCircle(centre, centre, radius, paint)
        paint.clearShadowLayer()
        paint.shader = LinearGradient(
            centre - radius, centre - radius, centre + radius, centre + radius,
            intArrayOf(
                blend(surface, Color.WHITE, if (dark) 0.055f else 0.32f),
                surface, blend(surface, Color.BLACK, if (dark) 0.12f else 0.045f),
            ), null, Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(centre, centre, radius, paint)
        paint.shader = null
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = s * 0.004f
        paint.color = withAlpha(Color.WHITE, if (dark) 0.16f else 0.80f)
        canvas.drawCircle(centre, centre, radius, paint)
        paint.strokeWidth = s * 0.002f
        paint.color = withAlpha(marks, 0.22f)
        canvas.drawCircle(centre, centre, radius - s * 0.021f, paint)
        paint.strokeCap = Paint.Cap.ROUND
        val p = progress.coerceIn(0.0, 1.0)
        for (i in 0 until 60) {
            val major = i % 5 == 0
            val angle = i * PI / 30 - PI / 2
            val dx = cos(angle).toFloat()
            val dy = sin(angle).toFloat()
            val outer = radius - s * 0.045f
            val inner = outer - s * if (major) 0.066f else 0.029f
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = s * if (major) 0.010f else 0.004f
            paint.color = if (i / 60.0 < p) withAlpha(accent, 0.45f)
                else withAlpha(marks, if (major) 0.85f else 0.52f)
            canvas.drawLine(centre + dx * inner, centre + dy * inner, centre + dx * outer, centre + dy * outer, paint)
            if (major) {
                paint.style = Paint.Style.FILL
                paint.typeface = labelTypeface
                paint.textSize = s * 0.032f
                paint.textAlign = Paint.Align.CENTER
                paint.color = marks
                val labelRadius = radius - s * 0.143f
                val baseline = centre + dy * labelRadius - (paint.ascent() + paint.descent()) / 2
                canvas.drawText(if (i == 0) "60" else i.toString(), centre + dx * labelRadius, baseline, paint)
            }
        }
        val angle = p * 2 * PI - PI / 2
        val dx = cos(angle).toFloat()
        val dy = sin(angle).toFloat()
        paint.style = Paint.Style.STROKE
        paint.color = accent
        paint.strokeWidth = s * 0.014f
        val inner = radius - s * 0.107f
        val outer = radius - s * 0.024f
        canvas.drawLine(centre + dx * inner, centre + dy * inner, centre + dx * outer, centre + dy * outer, paint)
        paint.style = Paint.Style.FILL
        val pinRadius = radius - s * 0.026f
        canvas.drawCircle(centre + dx * pinRadius, centre + dy * pinRadius, s * 0.017f, paint)
        // The live native countdown occupies the centre. These details stay
        // with the face and retain the app's proportions at every density.
        paint.textSize = s * 0.032f
        paint.textAlign = Paint.Align.CENTER
        paint.color = marks
        val remainingLabel = "R E M A I N I N G"
        canvas.drawText(remainingLabel, centre, centre - s * 0.088f, paint)
        paint.color = accent
        canvas.drawRoundRect(
            RectF(centre - s * 0.055f, centre + s * 0.113f, centre + s * 0.055f, centre + s * 0.125f),
            s * 0.006f, s * 0.006f, paint,
        )
        return bitmap
    }

    private fun withAlpha(color: Int, alpha: Float) = Color.argb(
        (alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color),
    )

    private fun blend(start: Int, end: Int, fraction: Float) = Color.rgb(
        (Color.red(start) + (Color.red(end) - Color.red(start)) * fraction).toInt(),
        (Color.green(start) + (Color.green(end) - Color.green(start)) * fraction).toInt(),
        (Color.blue(start) + (Color.blue(end) - Color.blue(start)) * fraction).toInt(),
    )
}
