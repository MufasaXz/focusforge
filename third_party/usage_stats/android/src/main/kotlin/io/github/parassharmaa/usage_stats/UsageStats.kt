package io.github.parassharmaa.usage_stats

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build

object UsageStats {
    private fun usageStatsManager(context: Context): UsageStatsManager =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

    /** Build a serializable map from a [UsageEvents.Event], guarding API-gated fields. */
    private fun eventToMap(event: UsageEvents.Event): Map<String, String?> {
        val map =
            hashMapOf<String, String?>(
                "eventType" to event.eventType.toString(),
                "timeStamp" to event.timeStamp.toString(),
                "packageName" to event.packageName,
                // className may legitimately be null for some events.
                "className" to event.className,
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            map["shortcutId"] = event.shortcutId
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            map["appStandbyBucket"] = event.appStandbyBucket.toString()
        }
        return map
    }

    fun queryEvents(
        context: Context,
        startDate: Long,
        endDate: Long,
    ): ArrayList<Map<String, String?>> {
        val usm = usageStatsManager(context)
        val events: UsageEvents = usm.queryEvents(startDate, endDate)
        val eventsList: ArrayList<Map<String, String?>> = arrayListOf()

        while (events.hasNextEvent()) {
            val event = UsageEvents.Event()
            events.getNextEvent(event)
            eventsList.add(eventToMap(event))
        }
        return eventsList
    }
}
