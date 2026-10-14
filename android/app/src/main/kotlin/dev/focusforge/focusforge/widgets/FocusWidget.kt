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
import android.os.Bundle
import android.os.Build
import android.util.TypedValue
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
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id, kind)
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
        if (intent.action == ACTION_REFRESH || intent.action == Intent.ACTION_CONFIGURATION_CHANGED || intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_TIME_CHANGED || intent.action == Intent.ACTION_TIMEZONE_CHANGED) refresh(context)
    }
    companion object {
        const val ACTION_REFRESH = "dev.focusforge.focusforge.WIDGET_REFRESH"
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(FocusWidget::class.java to "clock", DailyGoalWidget::class.java to "goal", StudyWidget::class.java to "study", WeeklyProgressWidget::class.java to "weekly").forEach { (provider, kind) ->
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
            val ink = Color.parseColor(if (dark) "#F2F4F7" else "#252B35")
            val secondary = Color.parseColor(if (dark) "#B8C0CC" else "#606977")
            val amoled = dark && prefs.getBoolean("flutter.ff.theme.amoled", false)
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
            val sessions = try { JSONArray(prefs.all["flutter.ff.sessions"] as? String ?: "[]") } catch (_: Exception) { JSONArray() }
            val user = try { JSONObject(prefs.all["flutter.ff.user"] as? String ?: "{}") } catch (_: Exception) { JSONObject() }
            val uid = user.opt("uid") as? String ?: ""
            val historyOwner = prefs.all["flutter.ff.achievements.historyOwner"] as? String ?: uid
            val aliases = try { JSONObject(prefs.all["flutter.ff.achievements.aliases"] as? String ?: "{}") } catch (_: Exception) { JSONObject() }
            val summary = WidgetSessionSummary.from(sessions, uid, historyOwner, aliases, now)
            val minutes = summary.todayMinutes
            val count = summary.todaySessions
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
            val savedPlan = try { JSONObject(prefs.getString("flutter.ff.goal.planner", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            val goalPlan = WidgetGoalPlan.resolve(savedPlan, java.time.LocalDate.now())
            val goal = goalPlan?.totalMinutes ?: 0
            val goalMinutes = if (goalPlan?.weekly == true) summary.totalMinutes else minutes
            val goalPeriod = if (goalPlan?.weekly == true) "this week" else "today"
            val goalText = when {
                goalPlan == null -> "Set a goal in FocusForge"
                goal == 0 -> if (goalPlan.weekly) "Rest week · No target" else "Rest day · No target"
                else -> "$goalMinutes / $goal min $goalPeriod"
            }
            val phase = when (timer.optString("phase", "focus")) {
                "shortBreak" -> "Short break"
                "longBreak" -> "Long break"
                else -> "Focus"
            }
            val target = timer.optLong("targetEnd", 0)
            val retroState = RetroWidgetState.from(timer, now)
            val running = retroState.running
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val refreshIntent = Intent(context, FocusWidget::class.java).apply { action = ACTION_REFRESH }
            val pending = PendingIntent.getBroadcast(context, id, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarm.cancel(pending)
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            // Chronometer already renders MM:SS, including leading zeroes.
            // A single boundary refresh stops it when the segment has ended.
            val nextRefresh = if (running) minOf(target, midnight) else midnight
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextRefresh, pending)
            val remaining = retroState.remainingMs
            val options = manager.getAppWidgetOptions(id)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
            if (kind == "weekly") {
                updateWeekly(context, manager, id, width, height, dark, amoled, ink, secondary, accent, summary)
                return
            }
            val compact = width < 190 || height < 190 || context.resources.configuration.fontScale > 1.3f
            val retroLayout = RetroWidgetLayout.forWidget(width, height, context.resources.configuration.fontScale)
            val hours = remaining / 3_600_000L
            val digits = if (hours > 0) hours.toString().length + 6 else 5
            val studyLayout = StudyWidgetLayout.forWidget(width, height, context.resources.configuration.fontScale, digits)
            val views = RemoteViews(context.packageName, when(kind) {
                "goal" -> if (compact) R.layout.ff_goal_widget_compact else R.layout.ff_goal_widget
                "study" -> R.layout.ff_study_widget
                else -> if (compact) R.layout.ff_focus_widget_compact else R.layout.ff_focus_widget
            })
            views.setInt(R.id.widget_root, "setBackgroundResource", when {
                amoled -> R.drawable.ff_widget_amoled
                dark -> R.drawable.ff_widget_dark
                else -> R.drawable.ff_widget_day
            })
            views.setTextColor(R.id.widget_title, secondary)
            views.setTextColor(R.id.widget_progress, if (kind == "goal") ink else secondary)
            views.setTextColor(R.id.widget_subject, if (kind == "goal") secondary else ink)
            if (kind != "goal") listOf(R.id.widget_time, R.id.widget_live).forEach { views.setTextColor(it, ink) }
            views.setTextColor(R.id.widget_caption, secondary)
            val scaledHeight = height / context.resources.configuration.fontScale
            views.setViewVisibility(R.id.widget_caption, if (scaledHeight < 160) View.GONE else View.VISIBLE)
            if (scaledHeight < 120 && kind != "clock") {
                // At 2× text the live value gets the space. Auxiliary labels
                // disappear instead of covering the countdown or goal ring.
                views.setViewVisibility(R.id.widget_title, View.GONE)
                views.setViewVisibility(R.id.widget_subject, View.GONE)
            }
            if (kind == "study") {
                views.setTextViewTextSize(R.id.widget_subject, TypedValue.COMPLEX_UNIT_SP, studyLayout.subjectSp)
                views.setViewVisibility(R.id.widget_title, if (studyLayout.showTitle) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_subject, if (studyLayout.showSubject) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_progress, if (studyLayout.showProgress) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_caption, if (studyLayout.showCaption) View.VISIBLE else View.GONE)
            }
            if (kind == "clock") {
                views.setViewVisibility(R.id.widget_title, if (retroLayout.showTitle) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_subject, if (retroLayout.showSubject) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_progress, if (retroLayout.showProgress) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_caption, if (retroLayout.showCaption) View.VISIBLE else View.GONE)
            }
            val padding = ((if (kind == "clock") retroLayout.paddingDp else if (kind == "study") studyLayout.paddingDp else if (compact) 12 else 18) * context.resources.displayMetrics.density).toInt()
            views.setViewPadding(R.id.widget_root, padding, padding, padding, padding)
            if (kind != "goal") {
                // Launcher dimensions are dp, so these constraints hold at
                // both low and high screen densities and large text settings.
                val timeSize = if (kind == "clock") retroLayout.countdownSp(remaining)
                    else studyLayout.countdownSp
                listOf(R.id.widget_time, R.id.widget_live).forEach {
                    views.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, timeSize)
                }
            }
            views.setTextViewText(R.id.widget_title, when(kind) {
                "goal" -> if (goalPlan?.weekly == true) "WEEKLY GOAL" else "TODAY’S GOAL"
                "study" -> if (running) "${phase.uppercase(Locale.ROOT)} IN PROGRESS" else "YOUR NEXT SESSION"
                else -> phase.uppercase(Locale.ROOT)
            })
            if (kind == "clock") {
                // The retro face carries its own centre label and accent pill.
                // State remains in the title/caption and spoken description.
                views.setViewVisibility(R.id.widget_phase, View.GONE)
            }
            views.setTextViewText(R.id.widget_subject, if (kind == "goal") count.toString() + " completed " + (if (count == 1) "session" else "sessions") else subject)
            val goalDisplayText = if (compact && goalPlan != null && goal > 0) "$goalMinutes / $goal min" else goalText
            views.setTextViewText(R.id.widget_progress, if (kind == "goal") goalDisplayText else WidgetSessionSummary.formatMinutes(minutes) + " focused today")
            if (kind == "goal") {
                val progressText = goalDisplayText
                val availableWidth = width - 2 * (if (compact) 12 else 18)
                val progressSp = min(if (compact) 12f else 15f, availableWidth / (context.resources.configuration.fontScale * progressText.length * .6f))
                views.setTextViewTextSize(R.id.widget_progress, TypedValue.COMPLEX_UNIT_SP, progressSp)
            }
            views.setTextViewText(R.id.widget_caption, if (kind == "goal") {
                when {
                    goalPlan == null -> "Tap to plan your subjects"
                    goal == 0 -> "Take your time · Tap to view"
                    goalMinutes >= goal -> "Goal complete · Keep growing"
                    else -> (goal - goalMinutes).toString() + " min to grow · Tap to view"
                }
            } else if (running) phase + " in progress · Tap to open" else if (remaining <= 0) "Block ended · Open to continue" else "Ready when you are · Tap to focus")
            if (kind == "goal") {
                views.setViewVisibility(R.id.widget_dial, if (goalPlan == null || goal == 0) View.GONE else View.VISIBLE)
                val progress = if (goal > 0) goalMinutes.toFloat() / goal else 0f
                views.setImageViewBitmap(R.id.widget_dial, goalRing(progress, dark, accent, ink, widgetTypeface(context), context.resources.configuration.fontScale))
                views.setContentDescription(R.id.widget_dial, if (goal > 0) (goalMinutes.toLong() * 100 / goal).coerceIn(0, 100).toString() + " percent of your goal $goalPeriod complete" else "No study target")
            } else {
                if (kind == "clock") {
                    val labelTypeface = widgetTypeface(context)
                    views.setImageViewBitmap(R.id.widget_dial, RetroWidgetRenderer.render(
                        (retroLayout.dialDp * context.resources.displayMetrics.density).roundToInt(),
                        retroState.progress, dark, amoled,
                        accent, secondary, labelTypeface,
                    ))
                    // All visible text stays native; decorative marks are not
                    // announced as another control in a screen reader.
                    views.setContentDescription(R.id.widget_root, "$phase timer, $subject, " +
                        (if (running) "in progress" else if (remaining <= 0) "complete" else "ready") +
                        ". Tap to open FocusForge.")
                }
                views.setViewVisibility(R.id.widget_live, if (running) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_time, if (running) View.GONE else View.VISIBLE)
                if (running) {
                    views.setChronometer(R.id.widget_live, SystemClock.elapsedRealtime() + remaining, "%s", true)
                    views.setChronometerCountDown(R.id.widget_live, true)
                } else {
                    val seconds = remaining.coerceAtLeast(0) / 1000
                    views.setTextViewText(R.id.widget_time, if (seconds >= 3600)
                        String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                        else String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60))
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
        private fun widgetTypeface(context: Context): Typeface = if (Build.VERSION.SDK_INT >= 26)
            context.resources.getFont(R.font.focus_widget_inter) else Typeface.create("sans-serif-medium", Typeface.NORMAL)

        private fun updateWeekly(
            context: Context, manager: AppWidgetManager, id: Int, width: Int, height: Int,
            dark: Boolean, amoled: Boolean, ink: Int, secondary: Int, accent: Int, summary: WidgetSessionSummary,
        ) {
            val headline = WidgetSessionSummary.formatMinutes(summary.totalMinutes)
            val scale = context.resources.configuration.fontScale
            val layout = WeeklyWidgetLayout.forWidget(width, height, scale, headline)
            val views = RemoteViews(context.packageName, R.layout.ff_weekly_widget)
            views.setInt(R.id.widget_root, "setBackgroundResource", when {
                amoled -> R.drawable.ff_widget_amoled
                dark -> R.drawable.ff_widget_dark
                else -> R.drawable.ff_widget_day
            })
            val density = context.resources.displayMetrics.density
            val padding = (layout.paddingDp * density).roundToInt()
            views.setViewPadding(R.id.widget_root, padding, padding, padding, padding)
            listOf(R.id.widget_title, R.id.widget_progress, R.id.widget_caption).forEach { views.setTextColor(it, secondary) }
            views.setTextColor(R.id.widget_time, ink)
            views.setTextViewText(R.id.widget_time, headline)
            views.setTextViewTextSize(R.id.widget_time, TypedValue.COMPLEX_UNIT_SP, layout.headlineSp)
            views.setTextViewTextSize(R.id.widget_progress, TypedValue.COMPLEX_UNIT_SP, layout.summarySp)
            val active = summary.activeDays
            views.setTextViewText(R.id.widget_progress, if (layout.shortSummary) "$active / 7 days" else "$active active ${if (active == 1) "day" else "days"}")
            views.setViewVisibility(R.id.widget_title, if (layout.showTitle) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_caption, if (layout.showCaption) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_caption, if (summary.totalMinutes == 0) "Your first block starts the week" else "Mon – Sun · Tap to view")
            val weekdayIds = listOf(R.id.week_mon, R.id.week_tue, R.id.week_wed, R.id.week_thu, R.id.week_fri, R.id.week_sat, R.id.week_sun)
            val names = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
            val labels = if ((width - 2 * layout.paddingDp) / scale >= 240) listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
                else listOf("M", "T", "W", "T", "F", "S", "S")
            weekdayIds.forEachIndexed { day, viewId ->
                views.setTextViewText(viewId, labels[day])
                views.setTextColor(viewId, if (day == summary.todayIndex) accent else secondary)
            }
            views.setImageViewBitmap(R.id.widget_dial, WeeklyWidgetRenderer.render(
                ((width - 2 * layout.paddingDp) * density).roundToInt(), (layout.chartHeightDp * density).roundToInt(), summary, accent, secondary,
            ))
            val spokenDays = names.mapIndexed { day, name -> "$name ${summary.dayMinutes[day]} minutes" }.joinToString(", ")
            views.setContentDescription(R.id.widget_root, "This week, $headline of completed focus, $active active days. Today is ${names[summary.todayIndex]}. $spokenDays. Tap to open your dashboard.")
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "dev.focusforge.focusforge.OPEN_WEEKLY"
                putExtra("open_dashboard", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            manager.updateAppWidget(id, views)
        }

        private fun goalRing(progress: Float, dark: Boolean, accent: Int, ink: Int, typeface: Typeface, fontScale: Float): Bitmap {
            val bitmap = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 20f; strokeCap = Paint.Cap.ROUND }
            // The track is the accent at a whisper of alpha rather than a fixed
            // gray, so the ring reads as one object in every palette and
            // theme while staying behind the arc it carries.
            pen.color = Color.argb(38, Color.red(accent), Color.green(accent), Color.blue(accent))
            canvas.drawCircle(160f, 160f, 137f, pen)
            pen.shader = LinearGradient(20f, 20f, 300f, 300f, intArrayOf(accent, Color.parseColor(if (dark) "#8DBA95" else "#56765B")), null, Shader.TileMode.CLAMP)
            canvas.drawArc(RectF(23f, 23f, 297f, 297f), -90f, 360f * progress.coerceIn(0f, 1f), false, pen)
            pen.shader = null
            pen.style = Paint.Style.FILL
            pen.color = ink
            pen.textAlign = Paint.Align.CENTER
            pen.typeface = typeface
            pen.textSize = 54f * fontScale.coerceIn(1f, 1.35f)
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
    }
}

class DailyGoalWidget : FocusWidget() { override val kind = "goal" }

class StudyWidget : FocusWidget() { override val kind = "study" }

class WeeklyProgressWidget : FocusWidget() { override val kind = "weekly" }
