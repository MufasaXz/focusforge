package dev.focusforge.focusforge.widgets

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import dev.focusforge.focusforge.MainActivity
import dev.focusforge.focusforge.R
import dev.focusforge.focusforge.localization.DeviceStrings
import org.json.JSONObject

/** System countdown, also eligible for compatible Android/OEM live bars. */
class FocusLiveActivity : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_DISMISSED) {
            context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE).edit()
                .putLong(DISMISSED_TARGET, intent.getLongExtra(TARGET_EXTRA, 0L)).apply()
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarm.cancel(refreshIntent(context))
            return
        }
        refresh(context)
        FocusWidget.refresh(context)
    }

    companion object {
        private const val CHANNEL = "focus_timer"
        private const val NOTIFICATION_ID = 4025
        private const val ALARM_ID = 4026
        private const val ACTION_REFRESH = "dev.focusforge.focusforge.FOCUS_LIVE_REFRESH"
        private const val ACTION_DISMISSED = "dev.focusforge.focusforge.FOCUS_LIVE_DISMISSED"
        private const val STATE_PREFS = "focusforge_live_activity"
        private const val DISMISSED_TARGET = "dismissed_target"
        private const val TARGET_EXTRA = "target_end"

        private fun refreshIntent(context: Context) = PendingIntent.getBroadcast(
            context, ALARM_ID, Intent(context, FocusLiveActivity::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun refresh(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pending = refreshIntent(context)
            alarm.cancel(pending)
            val activityState = context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val timer = try {
                JSONObject(prefs.getString("flutter.ff.focus.presets", "{}") ?: "{}")
            } catch (_: Exception) { JSONObject() }
            val now = System.currentTimeMillis()
            val target = timer.optLong("targetEnd", 0)
            val remaining = target - now
            if (!timer.optBoolean("running") || remaining <= 0) {
                manager.cancel(NOTIFICATION_ID)
                activityState.edit().remove(DISMISSED_TARGET).apply()
                return
            }
            // Android 14+ lets users dismiss ongoing notifications. Repeated
            // progress updates must respect that choice for this segment.
            if (activityState.getLong(DISMISSED_TARGET, 0L) == target) return
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                manager.cancel(NOTIFICATION_ID)
                return
            }
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(
                    CHANNEL, DeviceStrings.text(context, "Focus timer"), NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = DeviceStrings.text(context, "Your running focus or break countdown")
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                })
            }
            if (!manager.areNotificationsEnabled()) {
                manager.cancel(NOTIFICATION_ID)
                return
            }
            val hiddenDuration = timer.optBoolean("hideRandomDuration") && timer.optString("phase", "focus") == "focus"
            val phase = when (timer.optString("phase", "focus")) {
                "shortBreak" -> DeviceStrings.text(context, "Short break")
                "longBreak" -> DeviceStrings.text(context, "Long break")
                else -> DeviceStrings.text(context, "Focus")
            }
            val subject = timer.optString("subjectName")
                .takeIf { it.isNotBlank() && it != "null" } ?: DeviceStrings.text(context, "Time for yourself")
            val planned = timer.optLong("plannedMs", timer.optLong("remainingMs", remaining))
                .coerceAtLeast(remaining).coerceAtLeast(1)
            val progress = ((1.0 - remaining.toDouble() / planned) * 1000).toInt().coerceIn(0, 1000)
            val open = PendingIntent.getActivity(
                context, NOTIFICATION_ID, Intent(context, MainActivity::class.java).apply {
                    action = "dev.focusforge.focusforge.OPEN_FOCUS"
                    putExtra("open_focus", true)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val dismissed = PendingIntent.getBroadcast(
                context, NOTIFICATION_ID, Intent(context, FocusLiveActivity::class.java).apply {
                    action = ACTION_DISMISSED
                    putExtra(TARGET_EXTRA, target)
                }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
                else Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
            // The selected subject may be personal. A lock screen configured
            // to hide sensitive notifications receives only this countdown;
            // the full subject stays available after unlocking.
            @Suppress("DEPRECATION")
            val publicBuilder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
                else Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
            val publicVersion = publicBuilder
                .setSmallIcon(R.drawable.ic_focus_live)
                .setContentTitle(DeviceStrings.text(context, "FocusForge timer"))
                .setContentText(DeviceStrings.text(context, "Unlock to see your timer details"))
                .setCategory(Notification.CATEGORY_STOPWATCH)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setLocalOnly(true)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setWhen(target)
                .setShowWhen(!hiddenDuration)
                .setUsesChronometer(!hiddenDuration)
                .setChronometerCountDown(true)
                .build()
            builder
                .setSmallIcon(R.drawable.ic_focus_live)
                .setContentTitle(if (timer.optString("phase", "focus") == "focus") DeviceStrings.text(context, "Focusing · {0}", subject) else DeviceStrings.text(context, "{0} · Recharge", phase))
                .setContentText(DeviceStrings.text(context, "Tap to open your timer"))
                .setContentIntent(open)
                .setDeleteIntent(dismissed)
                .setCategory(Notification.CATEGORY_STOPWATCH)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setLocalOnly(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setColor(Color.rgb(118, 103, 71))
                .setWhen(target)
                .setShowWhen(!hiddenDuration)
                .setUsesChronometer(!hiddenDuration)
                .setChronometerCountDown(true)
                .setProgress(if (hiddenDuration) 0 else 1000, if (hiddenDuration) 0 else progress, false)
            if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(remaining)
            if (Build.VERSION.SDK_INT >= 36) {
                // The SDK hides the promotion setter behind a platform flag.
                // Its documented extra leaves final eligibility to Android.
                builder.addExtras(Bundle().apply {
                    putBoolean("android.requestPromotedOngoing", true)
                })
                // setWhen + countdown chronometer also drive the status chip.
                // Explicit short text would freeze it between refresh alarms.
            }
            try { manager.notify(NOTIFICATION_ID, builder.build()) }
            catch (_: SecurityException) { return } // Permission may change between checks.
            // The chrono owns seconds. Refresh only minute progress, including
            // when no launcher widget is installed.
            val nextMinute = remaining % 60_000L
            val next = now + (if (nextMinute < 1000) 60_000L else nextMinute)
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, minOf(target, next), pending)
        }
    }
}
