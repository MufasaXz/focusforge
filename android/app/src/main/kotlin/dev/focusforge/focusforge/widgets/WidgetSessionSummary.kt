package dev.focusforge.focusforge.widgets

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/** Uses local calendar boundaries and the same ownership rules as badges. */
internal data class WidgetSessionSummary(
    val dayMinutes: List<Int>,
    val todayIndex: Int,
    val todaySessions: Int,
    val mondayMs: Long,
) {
    val totalMinutes: Int get() = dayMinutes.fold(0L) { total, value -> total + value }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    val activeDays: Int get() = dayMinutes.count { it > 0 }
    val todayMinutes: Int get() = dayMinutes[todayIndex]

    companion object {
        fun from(
            sessions: JSONArray,
            currentUid: String,
            historyOwner: String,
            aliases: JSONObject,
            nowMs: Long,
            zone: TimeZone = TimeZone.getDefault(),
        ): WidgetSessionSummary {
            val today = Calendar.getInstance(zone).apply { timeInMillis = nowMs }
            val todayIndex = (today.get(Calendar.DAY_OF_WEEK) + 5) % 7
            val monday = (today.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                add(Calendar.DAY_OF_YEAR, -todayIndex)
            }
            val boundaries = LongArray(8) { index ->
                (monday.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, index) }.timeInMillis
            }
            val minutes = IntArray(7)
            var todaySessions = 0
            for (i in 0 until sessions.length()) {
                val session = sessions.optJSONObject(i) ?: continue
                if (!session.optBoolean("completed", true)) continue
                val owner = session.opt("ownerUid") as? String ?: ""
                val owned = (owner.isNotEmpty() && owner == currentUid) || aliases.opt(owner) == currentUid ||
                    (owner.isEmpty() && historyOwner == currentUid)
                if (!owned) continue
                val startedAt = (session.opt("startedAt") as? Number)?.toLong() ?: continue
                if (startedAt < boundaries[0] || startedAt >= boundaries[7] || startedAt > nowMs) continue
                val duration = (session.opt("minutes") as? Number)?.toLong()?.coerceIn(0, Int.MAX_VALUE.toLong()) ?: 0L
                if (duration <= 0L) continue
                val day = (0..6).first { startedAt < boundaries[it + 1] }
                minutes[day] = (minutes[day].toLong() + duration).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                if (day == todayIndex) todaySessions++
            }
            return WidgetSessionSummary(minutes.toList(), todayIndex, todaySessions, boundaries[0])
        }

        fun formatMinutes(minutes: Int): String = when {
            minutes >= 60 && minutes % 60 > 0 -> "${minutes / 60}h ${minutes % 60}m"
            minutes >= 60 -> "${minutes / 60}h"
            else -> "${minutes.coerceAtLeast(0)}m"
        }
    }
}
