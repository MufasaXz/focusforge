package dev.focusforge.focusforge.widgets

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.ZonedDateTime
import java.util.TimeZone

class WidgetSessionSummaryTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private fun at(value: String) = ZonedDateTime.parse(value).toInstant().toEpochMilli()
    private fun session(time: String, minutes: Int, owner: String = "alice", completed: Boolean = true) =
        JSONObject().put("startedAt", at(time)).put("minutes", minutes)
            .put("ownerUid", owner).put("completed", completed)

    @Test fun countsOnlyCurrentWeekCompletedOwnedTimeAndIdentifiesToday() {
        val sessions = JSONArray().put(session("2026-10-11T23:59:59Z", 80))
            .put(session("2026-10-12T00:00:00Z", 25))
            .put(session("2026-10-12T12:00:00Z", 35))
            .put(session("2026-10-13T12:00:00Z", 20, completed = false))
            .put(session("2026-10-14T09:00:00Z", 45))
            .put(session("2026-10-14T09:30:00Z", 100, owner = "bob"))
            .put(session("2026-10-14T13:00:00Z", 100))
            .put(session("2026-10-19T00:00:00Z", 200))
        val summary = WidgetSessionSummary.from(sessions, "alice", "alice", JSONObject(), at("2026-10-14T12:00:00Z"), utc)
        assertEquals(listOf(60, 0, 45, 0, 0, 0, 0), summary.dayMinutes)
        assertEquals(105, summary.totalMinutes)
        assertEquals(2, summary.activeDays)
        assertEquals(2, summary.todayIndex)
        assertEquals(45, summary.todayMinutes)
        assertEquals(1, summary.todaySessions)
    }

    @Test fun aliasesAttributeLinkedAnonymousTimeButLegacyTimeStaysWithHistoryOwner() {
        val sessions = JSONArray().put(session("2026-10-14T08:00:00Z", 20, owner = "anonymous"))
            .put(session("2026-10-14T09:00:00Z", 25, owner = ""))
            .put(session("2026-10-14T10:00:00Z", 30, owner = "alice"))
        val aliases = JSONObject().put("anonymous", "alice")
        val now = at("2026-10-14T12:00:00Z")
        assertEquals(75, WidgetSessionSummary.from(sessions, "alice", "alice", aliases, now, utc).totalMinutes)
        assertEquals(50, WidgetSessionSummary.from(sessions, "alice", "bob", aliases, now, utc).totalMinutes)
        assertEquals(25, WidgetSessionSummary.from(sessions, "bob", "bob", aliases, now, utc).totalMinutes)
        assertEquals(0, WidgetSessionSummary.from(sessions, "", "alice", aliases, now, utc).totalMinutes)
    }

    @Test fun sundayAndDstUseLocalCalendarDaysRatherThanFixedTwentyFourHourOffsets() {
        val zone = TimeZone.getTimeZone("America/New_York")
        val sessions = JSONArray().put(session("2026-11-01T00:00:00-04:00", 25))
            .put(session("2026-11-01T23:30:00-05:00", 35))
            .put(session("2026-10-25T23:59:59-04:00", 80))
        val summary = WidgetSessionSummary.from(sessions, "alice", "alice", JSONObject(), at("2026-11-01T23:59:59-05:00"), zone)
        assertEquals(listOf(0, 0, 0, 0, 0, 0, 60), summary.dayMinutes)
        assertEquals(6, summary.todayIndex)
        assertEquals(2, summary.todaySessions)
        assertEquals(at("2026-10-26T00:00:00-04:00"), summary.mondayMs)
    }

    @Test fun damagedEntriesAndEmptyHistoryCannotInflateTotals() {
        val sessions = JSONArray().put(JSONObject().put("minutes", 100))
            .put(session("2026-10-14T09:00:00Z", -30))
            .put("not a session")
            .put(session("2026-10-14T09:00:00Z", 0))
            .put(session("2026-10-14T09:00:00Z", 25).removeAndReturn("completed"))
        val summary = WidgetSessionSummary.from(sessions, "alice", "alice", JSONObject(), at("2026-10-14T12:00:00Z"), utc)
        assertEquals(25, summary.totalMinutes)
        assertEquals(1, summary.activeDays)
        assertEquals(1, summary.todaySessions)
        assertEquals(0, WidgetSessionSummary.from(JSONArray(), "alice", "alice", JSONObject(), at("2026-10-14T12:00:00Z"), utc).totalMinutes)
    }

    private fun JSONObject.removeAndReturn(key: String): JSONObject = apply { remove(key) }
}
