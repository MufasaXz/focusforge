package dev.focusforge.focusforge.assistant

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import dev.focusforge.focusforge.MainActivity
import dev.focusforge.focusforge.R
import dev.focusforge.focusforge.localization.DeviceStrings

/**
 * Pip's reminder: at most one pending notification, written and timed by the
 * app, shown as a message from Pip with its head as the sender's picture.
 *
 * The app decides whether and when to remind, in the user's language, and
 * moves or cancels the reminder whenever the user studies. This side only
 * keeps the words until the alarm and survives reboots.
 */
object PipNudges {
    private const val CHANNEL = "pip_reminders"
    private const val PREFS = "pip_nudges"
    private const val KEY_AT = "at"
    private const val KEY_TITLE = "title"
    private const val KEY_BODY = "body"
    private const val NOTIFICATION_ID = 4107

    /** A reminder this late (the phone was off all evening) is dropped. */
    private const val STALE_MS = 3 * 60 * 60 * 1000L

    fun schedule(context: Context, atMillis: Long, title: String, body: String) {
        prefs(context).edit()
            .putLong(KEY_AT, atMillis)
            .putString(KEY_TITLE, title)
            .putString(KEY_BODY, body)
            .apply()
        arm(context, atMillis)
    }

    fun cancel(context: Context) {
        prefs(context).edit().clear().apply()
        context.getSystemService(AlarmManager::class.java)?.cancel(alarm(context))
    }

    /** Alarms do not survive a reboot or an app update, so a pending one is set again. */
    fun rearm(context: Context) {
        val at = prefs(context).getLong(KEY_AT, 0L)
        if (at <= 0L) return
        val now = System.currentTimeMillis()
        if (now - at > STALE_MS) return cancel(context)
        arm(context, maxOf(at, now + 60_000L))
    }

    internal fun post(context: Context) {
        val stored = prefs(context)
        val at = stored.getLong(KEY_AT, 0L)
        val title = stored.getString(KEY_TITLE, null)
        val body = stored.getString(KEY_BODY, null)
        stored.edit().clear().apply()
        if (title.isNullOrBlank() || body.isNullOrBlank()) return
        if (System.currentTimeMillis() - at > STALE_MS) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!canNotify(context, manager)) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                DeviceStrings.text(context, "Pip’s reminders"),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = DeviceStrings.text(context, "A study nudge from Pip on days you have not studied")
            },
        )

        val head = BitmapFactory.decodeResource(context.resources, R.drawable.pip_head)
        val open = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            Intent(context, MainActivity::class.java).apply {
                putExtra("open_dashboard", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_focus_live)
            .setLargeIcon(head)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Pip "sends" the reminder: its head is the avatar, its name the sender.
            val pip = Person.Builder()
                .setName("Pip")
                .setKey("pip")
                .setBot(true)
                .setIcon(Icon.createWithBitmap(head))
                .build()
            val user = Person.Builder().setName(DeviceStrings.text(context, "You")).build()
            builder.setStyle(
                Notification.MessagingStyle(user)
                    .addMessage("$title\n$body", System.currentTimeMillis(), pip),
            )
        } else {
            builder.setStyle(Notification.BigTextStyle().bigText("$title\n$body"))
        }
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun canNotify(context: Context, manager: NotificationManager): Boolean {
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun arm(context: Context, atMillis: Long) {
        // Inexact on purpose: a reminder a few minutes late is fine, and an
        // inexact alarm needs no exact-alarm permission.
        context.getSystemService(AlarmManager::class.java)
            ?.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, alarm(context))
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        NOTIFICATION_ID,
        Intent(context, PipNudgeReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Fires Pip's reminder when its alarm goes off. */
class PipNudgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        PipNudges.post(context.applicationContext)
    }
}
