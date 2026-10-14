package dev.focusforge.focusforge.widgets
import org.json.JSONObject
import java.time.LocalDate
import java.time.DayOfWeek
import java.time.temporal.TemporalAdjusters

/** Mirrors the saved day/recurring Monday-week planner without inventing goals. */
internal data class WidgetGoalPlan(val totalMinutes:Int,val weekly:Boolean) {
    companion object {
        fun resolve(saved:JSONObject,today:LocalDate):WidgetGoalPlan? =
            read(saved.optJSONObject("day"),today,false) ?: read(saved.optJSONObject("week"),today,true)
        private fun read(raw:JSONObject?,today:LocalDate,weekly:Boolean):WidgetGoalPlan? {
            if(raw == null || raw.optString("scope") != if(weekly) "week" else "day") return null
            val date = try { LocalDate.parse(raw.optString("date").take(10)) } catch(_:Exception) { return null }
            if(weekly) {
                if(today.isBefore(date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)))) return null
            } else if(date != today) return null
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
            if(sum != total.toLong()) return null
            return WidgetGoalPlan(total.toInt(),weekly)
        }
    }
}
