package dev.focusforge.focusforge.widgets
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
class WidgetGoalPlanTest {
    private fun plan(scope:String,date:String,total:Int=480) = JSONObject()
        .put("scope",scope).put("date",date+"T00:00:00.000")
        .put("totalMinutes",total).put("subjectMinutes",JSONObject().put("math",total))
    @Test fun noSavedPlanDoesNotInventAGoal() {
        assertNull(WidgetGoalPlan.resolve(JSONObject(),LocalDate.of(2026,10,14)))
    }
    @Test fun oneDayOverridesWeekAndExpiresNextDay() {
        val saved = JSONObject().put("day",plan("day","2026-10-14",120)).put("week",plan("week","2026-10-12"))
        assertEquals(120,WidgetGoalPlan.resolve(saved,LocalDate.of(2026,10,14))?.totalMinutes)
        assertEquals(480,WidgetGoalPlan.resolve(saved,LocalDate.of(2026,10,15))?.totalMinutes)
        assertTrue(WidgetGoalPlan.resolve(saved,LocalDate.of(2026,10,15))!!.weekly)
    }
    @Test fun weeklyTemplateRepeatsAndRestGoalRemainsExplicit() {
        assertEquals(480,WidgetGoalPlan.resolve(JSONObject().put("week",plan("week","2026-10-12")),LocalDate.of(2026,10,19))?.totalMinutes)
        assertEquals(0,WidgetGoalPlan.resolve(JSONObject().put("day",plan("day","2026-10-14",0)),LocalDate.of(2026,10,14))?.totalMinutes)
    }
    @Test fun inconsistentOrFutureAllocationsAreRejected() {
        val malformed=plan("week","2026-10-12").put("subjectMinutes",JSONObject().put("math",60))
        assertNull(WidgetGoalPlan.resolve(JSONObject().put("week",malformed),LocalDate.of(2026,10,14)))
        assertNull(WidgetGoalPlan.resolve(JSONObject().put("week",plan("week","2026-10-19")),LocalDate.of(2026,10,14)))
    }
}
