package dev.focusforge.focusforge.widgets

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RetroWidgetModelTest {
    @Test fun runningDialUsesTheDeadlineInsteadOfAStaleSavedRemainder() {
        val timer = JSONObject("""{"running":true,"targetEnd":1000000,"remainingMs":1200000,"plannedMs":1200000}""")
        val state = RetroWidgetState.from(timer, nowMs = 100000)
        assertEquals(900000L, state.remainingMs)
        assertEquals(0.25, state.progress, 0.00001)
        assertTrue(state.running)
    }

    @Test fun randomFocusDoesNotRevealProgressOnTheDial() {
        val state = RetroWidgetState.from(
            JSONObject("""{"running":true,"targetEnd":1000000,"plannedMs":1200000,"phase":"focus","hideRandomDuration":true}"""),
            nowMs = 100000,
        )
        assertTrue(state.hideDuration)
        assertEquals(0.0, state.progress, 0.00001)
        val resting = RetroWidgetState.from(JSONObject("""{"phase":"shortBreak","hideRandomDuration":true}"""), 100000)
        assertFalse(resting.hideDuration)
    }

    @Test fun pausedDialKeepsItsProgressAndIgnoresTheOldDeadline() {
        val state = RetroWidgetState.from(
            JSONObject("""{"running":false,"targetEnd":1000000,"remainingMs":300000,"plannedMs":1200000}"""),
            nowMs = 100000,
        )
        assertEquals(300000L, state.remainingMs)
        assertEquals(0.75, state.progress, 0.00001)
        assertFalse(state.running)
    }

    @Test fun expiredRunningDialStopsAtCompletion() {
        val state = RetroWidgetState.from(
            JSONObject("""{"running":true,"targetEnd":1000,"remainingMs":60000,"plannedMs":1200000}"""),
            nowMs = 2000,
        )
        assertEquals(0L, state.remainingMs)
        assertEquals(1.0, state.progress, 0.00001)
        assertFalse(state.running)
    }

    @Test fun legacySnapshotsAndInvalidDurationsDoNotProduceInvalidProgress() {
        val legacy = RetroWidgetState.from(JSONObject("""{"remainingMs":600000}"""), 100000)
        assertEquals(600000L, legacy.remainingMs)
        assertEquals(0.0, legacy.progress, 0.00001)
        val invalid = RetroWidgetState.from(
            JSONObject("""{"remainingMs":-600000,"plannedMs":0}"""), 100000,
        )
        assertEquals(0L, invalid.remainingMs)
        assertTrue(invalid.progress.isFinite())
        val extended = RetroWidgetState.from(
            JSONObject("""{"remainingMs":1800000,"plannedMs":1200000}"""), 100000,
        )
        assertEquals(0.0, extended.progress, 0.00001)
    }

    @Test fun defaultDialStartsAtTwentyFiveMinutes() {
        val state = RetroWidgetState.from(JSONObject(), 100000)
        assertEquals(1500000L, state.remainingMs)
        assertEquals(0.0, state.progress, 0.00001)
    }

    @Test fun narrowAndLargeTextWidgetsKeepTheLiveValueInsideTheDial() {
        for ((width, height, scale) in listOf(
            Triple(140, 140, 1f), Triple(180, 180, 2f),
            Triple(220, 180, 1f), Triple(320, 220, 2f), Triple(320, 320, 1f),
        )) {
            val layout = RetroWidgetLayout.forWidget(width, height, scale)
            val timeSp = layout.countdownSp(5400000L)
            assertTrue("The dial must fit the available width", layout.dialDp <= width - layout.paddingDp * 2)
            assertTrue("The dial must fit the available height", layout.dialDp <= height - layout.paddingDp * 2)
            assertTrue("A seven-digit countdown must not cover the minute marks",
                timeSp * scale * 7 * 0.59f <= layout.dialDp * 0.58f + 0.01f)
            assertTrue(timeSp.isFinite() && timeSp > 0f)
        }
    }

    @Test fun shortLargeTextWidgetsGiveTheDialSpaceBeforeSecondaryLabels() {
        val layout = RetroWidgetLayout.forWidget(140, 140, 2f)
        assertFalse(layout.showTitle)
        assertFalse(layout.showSubject)
        assertFalse(layout.showProgress)
        assertFalse(layout.showCaption)
        assertTrue(layout.dialDp >= 100f)
    }
}
