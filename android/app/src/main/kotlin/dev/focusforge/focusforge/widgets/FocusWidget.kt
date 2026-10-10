package dev.focusforge.focusforge.widgets

import android.app.PendingIntent
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.*
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import dev.focusforge.focusforge.MainActivity
import dev.focusforge.focusforge.R
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import kotlin.math.*

/** Widgets read the same local deadline and completed sessions as Flutter. */
open class FocusWidget : AppWidgetProvider() {
    protected open val kind = "clock"
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it, kind) }
    }
    override fun onDeleted(context: Context, ids: IntArray) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ids.forEach { id ->
            val intent = Intent(context, FocusWidget::class.java).apply { action = ACTION_REFRESH }
            alarm.cancel(PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH || intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_TIME_CHANGED || intent.action == Intent.ACTION_TIMEZONE_CHANGED) refresh(context)
    }
    companion object {
        const val ACTION_REFRESH = "dev.focusforge.focusforge.WIDGET_REFRESH"
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(FocusWidget::class.java to "clock", DailyGoalWidget::class.java to "goal", StudyWidget::class.java to "study").forEach { (provider, kind) ->
                manager.getAppWidgetIds(ComponentName(context, provider)).forEach { update(context, manager, it, kind) }
            }
        }
        private fun update(context: Context, manager: AppWidgetManager, id: Int, kind: String) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val dark = when (prefs.getString("flutter.ff.theme", "system")) {
                "dark" -> true
                "light" -> false
                else -> context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            }
            val ink = Color.parseColor(if (dark) "#F4EEE3" else "#302D26")
            val secondary = Color.parseColor(if (dark) "#BDB6AA" else "#6C6557")
            val accent = Color.parseColor(when (prefs.getString("flutter.ff.theme.palette", "parchment")) {
                "ember" -> if (dark) "#FF8A50" else "#B64E20"
                "tide" -> if (dark) "#6FA8FF" else "#1B6FD6"
                "grove" -> if (dark) "#6FD39A" else "#2E7D4F"
                "iris" -> if (dark) "#B49BFF" else "#6A4BC7"
                "rose" -> if (dark) "#FF8FB1" else "#C2185B"
                "slate" -> if (dark) "#9AA7BD" else "#4A5568"
                else -> if (dark) "#D9C8A3" else "#766747"
            })
            val now = System.currentTimeMillis()
            var minutes = 0
            var count = 0
            try {
                val sessions = JSONArray(prefs.getString("flutter.ff.sessions", "[]"))
                val today = Calendar.getInstance()
                for (i in 0 until sessions.length()) {
                    val session = sessions.optJSONObject(i) ?: continue
                    val at = Calendar.getInstance().apply { timeInMillis = session.optLong("startedAt") }
                    if (session.optBoolean("completed", true) && at.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                        at.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)) {
                        minutes += session.optInt("minutes").coerceAtLeast(0)
                        count++
                    }
                }
            } catch (_: Exception) { }
            val timer = try { JSONObject(prefs.getString("flutter.ff.focus.presets", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            val subjectId = timer.optString("subjectId")
            var subject = timer.optString("subjectName").takeIf { it.isNotBlank() && it != "null" } ?: "Choose a subject"
            try {
                val subjects = JSONArray(prefs.getString("flutter.ff.subjects", "[]"))
                if (prefs.contains("flutter.ff.subjects")) subject = "Choose a subject"
                for (i in 0 until subjects.length()) {
                    val item = subjects.optJSONObject(i) ?: continue
                    if (item.optString("id") == subjectId) subject = item.optString("name", subject)
                }
            } catch (_: Exception) { }
            val weekday = (Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            val defaultGoal = prefs.getLong("flutter.ff.goal.daily", 300).toInt().coerceIn(30, 480)
            val overrides = try { JSONObject(prefs.getString("flutter.ff.goal.days", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            val override = overrides.optInt(weekday.toString(), 0)
            val goal = if (override > 0) override.coerceIn(30, 480) else defaultGoal
            val phase = when (timer.optString("phase", "focus")) {
                "shortBreak" -> "Short break"
                "longBreak" -> "Long break"
                else -> "Focus"
            }
            val target = timer.optLong("targetEnd", 0)
            val running = timer.optBoolean("running") && target > now
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val refreshIntent = Intent(context, FocusWidget::class.java).apply { action = ACTION_REFRESH }
            val pending = PendingIntent.getBroadcast(context, id, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarm.cancel(pending)
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, if (running) minOf(target, midnight) else midnight, pending)
            val remaining = if (running) target - now else if (timer.optBoolean("running")) 0L else timer.optLong("remainingMs", 25 * 60_000L)
            val views = RemoteViews(context.packageName, when(kind) {
                "goal" -> R.layout.ff_goal_widget
                "study" -> R.layout.ff_study_widget
                else -> R.layout.ff_focus_widget
            })
            views.setInt(R.id.widget_root, "setBackgroundResource", if (dark) R.drawable.ff_widget_dark else R.drawable.ff_widget_day)
            listOf(R.id.widget_title, R.id.widget_progress, R.id.widget_subject).forEach { views.setTextColor(it, ink) }
            if (kind != "goal") listOf(R.id.widget_time, R.id.widget_live).forEach { views.setTextColor(it, ink) }
            views.setTextColor(R.id.widget_caption, secondary)
            views.setTextViewText(R.id.widget_title, if (kind == "goal") "DAILY GOAL" else "FOCUSFORGE · " + phase.uppercase(Locale.ROOT))
            views.setTextViewText(R.id.widget_subject, if (kind == "goal") count.toString() + " completed " + (if (count == 1) "session" else "sessions") else subject)
            views.setTextViewText(R.id.widget_progress, minutes.toString() + " / " + goal + " min today")
            views.setTextViewText(R.id.widget_caption, if (kind == "goal") {
                if (minutes >= goal) "Goal complete · Keep growing" else (goal - minutes).toString() + " min to grow · Tap to view"
            } else if (running) phase + " in progress · Tap to open" else if (remaining <= 0) "Block ended · Open to continue" else "Ready when you are · Tap to focus")
            if (kind == "goal") {
                views.setImageViewBitmap(R.id.widget_dial, goalRing(minutes.toFloat() / goal, dark, accent, ink))
                views.setContentDescription(R.id.widget_dial, (minutes * 100 / goal).coerceIn(0, 100).toString() + " percent of today's goal complete")
            } else {
                if (kind == "clock") views.setImageViewBitmap(R.id.widget_dial, dial(dark, secondary, accent))
                views.setViewVisibility(R.id.widget_live, if (running) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_time, if (running) View.GONE else View.VISIBLE)
                if (running) {
                    views.setChronometer(R.id.widget_live, SystemClock.elapsedRealtime() + remaining, "%s", true)
                    views.setChronometerCountDown(R.id.widget_live, true)
                } else {
                    val seconds = remaining.coerceAtLeast(0) / 1000
                    views.setTextViewText(R.id.widget_time, String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60))
                    views.setChronometer(R.id.widget_live, SystemClock.elapsedRealtime(), "%s", false)
                }
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "dev.focusforge.focusforge.OPEN_" + kind.uppercase(Locale.ROOT)
                putExtra(if (kind == "goal") "open_dashboard" else "open_focus", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            manager.updateAppWidget(id, views)
        }
        private fun goalRing(progress: Float, dark: Boolean, accent: Int, ink: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 20f; strokeCap = Paint.Cap.ROUND }
            pen.color = Color.parseColor(if (dark) "#444541" else "#DED1B9")
            canvas.drawCircle(160f, 160f, 137f, pen)
            pen.shader = LinearGradient(20f, 20f, 300f, 300f, intArrayOf(accent, Color.parseColor(if (dark) "#8DBA95" else "#56765B")), null, Shader.TileMode.CLAMP)
            canvas.drawArc(RectF(23f, 23f, 297f, 297f), -90f, 360f * progress.coerceIn(0f, 1f), false, pen)
            pen.shader = null
            pen.style = Paint.Style.FILL
            pen.color = ink
            pen.textAlign = Paint.Align.CENTER
            pen.typeface = Typeface.create("sans-serif", Typeface.BOLD)
            pen.textSize = 54f
            canvas.drawText((progress.coerceIn(0f, 1f) * 100).roundToInt().toString() + "%", 160f, 189f, pen)
            pen.color = accent
            val leaf = Path().apply { moveTo(160f, 124f); cubicTo(146f, 101f, 166f, 82f, 190f, 80f); cubicTo(191f, 106f, 180f, 121f, 160f, 124f); close() }
            canvas.drawPath(leaf, pen)
            val left = Path().apply { moveTo(160f, 126f); cubicTo(139f, 130f, 126f, 114f, 125f, 98f); cubicTo(147f, 98f, 162f, 111f, 160f, 126f); close() }
            canvas.drawPath(left, pen)
            pen.style = Paint.Style.STROKE; pen.strokeWidth = 3f
            canvas.drawLine(160f, 135f, 165f, 112f, pen)
            return bitmap
        }
        private fun dial(dark: Boolean, marks: Int, accent: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(360, 360, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.shader = LinearGradient(0f, 0f, 360f, 360f, Color.parseColor(if (dark) "#373735" else "#E7DEC9"), Color.parseColor(if (dark) "#232426" else "#D4C8AD"), Shader.TileMode.CLAMP)
            canvas.drawCircle(180f, 180f, 173f, paint)
            paint.shader = null
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2f
            paint.color = Color.argb(if (dark) 50 else 220, 255, 255, 255)
            canvas.drawCircle(180f, 180f, 172f, paint)
            for (i in 0 until 60) {
                val angle = i * PI / 30 - PI / 2
                val major = i % 5 == 0
                val inner = if (major) 133 else 147
                paint.color = marks
                paint.strokeWidth = if (major) 3.5f else 1.5f
                canvas.drawLine((180 + cos(angle) * inner).toFloat(), (180 + sin(angle) * inner).toFloat(), (180 + cos(angle) * 157).toFloat(), (180 + sin(angle) * 157).toFloat(), paint)
                if (major) {
                    paint.style = Paint.Style.FILL
                    paint.textSize = 12f
                    paint.typeface = Typeface.MONOSPACE
                    paint.textAlign = Paint.Align.CENTER
                    canvas.drawText(if (i == 0) "60" else i.toString(), (180 + cos(angle) * 120).toFloat(), (184 + sin(angle) * 120).toFloat(), paint)
                    paint.style = Paint.Style.STROKE
                }
            }
            paint.color = accent
            paint.strokeWidth = 5f
            canvas.drawLine(180f, 9f, 180f, 35f, paint)
            return bitmap
        }
    }
}

class DailyGoalWidget : FocusWidget() { override val kind = "goal" }

class StudyWidget : FocusWidget() { override val kind = "study" }
