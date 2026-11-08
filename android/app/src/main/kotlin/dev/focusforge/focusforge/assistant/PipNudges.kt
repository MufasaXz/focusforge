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
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Pip's reminders: the evening nudge, the exam countdown and the timetable's
 * daily call, each shown as a message from Pip with its head as the sender's
 * picture.
 *
 * The app decides whether, when and what to remind, in the user's language,
 * and hands over the whole list whenever it changes. This side keeps the
 * list until each alarm and survives reboots.
 */
object PipNudges {
    private const val CHANNEL = "pip_reminders"
    private const val PREFS = "pip_nudges"
    private const val KEY_ITEMS = "items"
    private const val EXTRA_ID = "pip_reminder_id"
    private const val NOTIFICATION_BASE = 4100

    /** Marks Pip's posted notifications, so [clear] can find them again. */
    private const val TAG = "pip"


    data class Reminder(
        val id: Int,
        val at: Long,
        val title: String,
        val body: String,
        /** How late it may still go out, if the phone was off at [at]. */
        val staleMs: Long,
    )

    /** Replaces every pending reminder with [reminders]. */
    fun schedule(context: Context, reminders: List<Reminder>) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (old in load(context)) alarms?.cancel(alarm(context, old.id))
        save(context, reminders)
        for (reminder in reminders) arm(context, reminder.id, reminder.at)
    }

    /**
     * Cancels every pending reminder and removes any already in the shade,
     * as when the account is deleted: their titles can name its tasks.
     */
    fun clear(context: Context) {
        schedule(context, emptyList())
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        for (shown in manager.activeNotifications) {
            val pips = shown.tag == TAG ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    shown.notification.channelId == CHANNEL)
            if (pips) manager.cancel(shown.tag, shown.id)
        }
    }

    /** Alarms do not survive a reboot or an app update, so pending ones are set again. */
    fun rearm(context: Context) {
        val now = System.currentTimeMillis()
        val live = load(context).filter { now - it.at <= it.staleMs }
        save(context, live)
        for (reminder in live) arm(context, reminder.id, maxOf(reminder.at, now + 60_000L))
    }

    internal fun post(context: Context, id: Int) {
        val pending = load(context)
        val reminder = pending.firstOrNull { it.id == id } ?: return
        save(context, pending.filter { it.id != id })
        if (System.currentTimeMillis() - reminder.at > reminder.staleMs) return
        val title = reminder.title
        val body = reminder.body
        if (title.isBlank() || body.isBlank()) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!canNotify(context, manager)) return
        // Channels arrived in Android 8; Android 7 posts with a priority instead.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    DeviceStrings.text(context, "Pip’s reminders"),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = DeviceStrings.text(context, "Study reminders from Pip for your timetable, your exam and days without study")
                },
            )
        }

        val head = BitmapFactory.decodeResource(context.resources, R.drawable.pip_head)
        val open = PendingIntent.getActivity(
            context,
            NOTIFICATION_BASE + id,
            Intent(context, MainActivity::class.java).apply {
                putExtra("open_dashboard", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CHANNEL)
            else Notification.Builder(context).setPriority(Notification.PRIORITY_DEFAULT)
        builder
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
        manager.notify(TAG, NOTIFICATION_BASE + id, builder.build())
    }

    private fun canNotify(context: Context, manager: NotificationManager): Boolean {
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun arm(context: Context, id: Int, atMillis: Long) {
        // Inexact on purpose: a reminder a few minutes late is fine, and an
        // inexact alarm needs no exact-alarm permission.
        context.getSystemService(AlarmManager::class.java)
            ?.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, alarm(context, id))
    }

    private fun alarm(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        NOTIFICATION_BASE + id,
        Intent(context, PipNudgeReceiver::class.java).putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    internal fun idOf(intent: Intent?): Int? =
        intent?.takeIf { it.hasExtra(EXTRA_ID) }?.getIntExtra(EXTRA_ID, 0)

    private fun load(context: Context): List<Reminder> {
        val raw = prefs(context).getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            List(array.length()) { i ->
                val item = array.getJSONObject(i)
                Reminder(
                    id = item.getInt("id"),
                    at = item.getLong("at"),
                    title = item.getString("title"),
                    body = item.getString("body"),
                    staleMs = item.getLong("stale"),
                )
            }
        } catch (_: JSONException) {
            emptyList()
        }
    }

    private fun save(context: Context, reminders: List<Reminder>) {
        val array = JSONArray()
        for (reminder in reminders) {
            array.put(
                JSONObject()
                    .put("id", reminder.id)
                    .put("at", reminder.at)
                    .put("title", reminder.title)
                    .put("body", reminder.body)
                    .put("stale", reminder.staleMs),
            )
        }
        prefs(context).edit().putString(KEY_ITEMS, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/** Fires Pip's reminder when its alarm goes off. */
class PipNudgeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val id = PipNudges.idOf(intent) ?: return
        PipNudges.post(context.applicationContext, id)
    }
}
