package dev.focusforge.focusforge.widgets
import org.json.JSONObject
import java.time.LocalDate

/** Mirrors the daily planner; retired weekly plans never become today's goal. */
internal data class WidgetGoalPlan(val totalMinutes:Int,val weekly:Boolean) {
    companion object {
        fun resolve(saved:JSONObject,today:LocalDate):WidgetGoalPlan? =
            read(saved.optJSONObject("day"),today,false)
        private fun read(raw:JSONObject?,today:LocalDate,weekly:Boolean):WidgetGoalPlan? {
            if(raw == null || raw.optString("scope") != if(weekly) "week" else "day") return null
            val date = try { LocalDate.parse(raw.optString("date").take(10)) } catch(_:Exception) { return null }
            val end = if(raw.optBoolean("repeatThisWeek",false))
                date.plusDays((7-date.dayOfWeek.value).toLong()) else date
            if(today.isBefore(date) || today.isAfter(end)) return null
            val totalValue = raw.opt("totalMinutes") as? Number ?: return null
            val total = totalValue.toDouble()
            if(total < 0 || total > 720 || total != total.toInt().toDouble()) return null
            val subjects = raw.optJSONObject("subjectMinutes") ?: return null
            var sum = 0L
            for(key in subjects.keys()) {
                if(key.isBlank()) return null
                val value = (subjects.opt(key) as? Number)?.toDouble() ?: return null
                if(value < 0 || value > 720 || value != value.toInt().toDouble()) return null
                sum += value.toInt()
            }
            if(sum > 0L && sum != total.toLong()) return null
            return WidgetGoalPlan(total.toInt(),weekly)
        }
    }
}
