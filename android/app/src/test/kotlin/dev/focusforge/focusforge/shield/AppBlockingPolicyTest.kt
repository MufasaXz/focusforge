package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class AppBlockingPolicyTest {
    private val packageName = "com.example.distraction"
    private fun rules(mode: RuleMode = RuleMode.BLOCK, budget: Int = 30,
                      focus: Long? = null, strict: Long? = null) = ShieldRules(
        mapOf(packageName to AppRule(packageName, "Distraction", mode, budget)),
        YoutubeRules.OFF, 300, strict, focus,
    )

    @Test fun protectedPackagesAreNeverBlockedEvenDuringStrictMode() {
        assertNull(AppBlockingPolicy.reason(packageName, rules(strict = 2000), 1000,
            0, setOf(packageName), 999999))
    }
    @Test fun temporaryAccessEndsAtItsDeadline() {
        assertNull(AppBlockingPolicy.reason(packageName, rules(), 1000, 1001, emptySet(), 0))
        assertNotNull(AppBlockingPolicy.reason(packageName, rules(), 1001, 1001, emptySet(), 0))
    }
    @Test fun focusAndStrictWindowsEndWithoutFlutterRunning() {
        assertNotNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.FOCUS, focus = 1500),
            1000, 0, emptySet(), 0))
        assertNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.FOCUS, focus = 1500),
            1500, 0, emptySet(), 0))
        assertNotNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.BUDGET, strict = 1500),
            1000, 0, emptySet(), 0))
        assertNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.BUDGET, strict = 1500),
            1500, 0, emptySet(), 0))
    }
    @Test fun budgetNeedsKnownUsageAndFiresAtAllowance() {
        assertNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.BUDGET), 1000,
            0, emptySet(), null))
        assertNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.BUDGET), 1000,
            0, emptySet(), 1799999))
        assertNotNull(AppBlockingPolicy.reason(packageName, rules(RuleMode.BUDGET), 1000,
            0, emptySet(), 1800000))
    }
    @Test fun overlappingUsageQueriesDoNotRestoreAnOlderForeground() {
        val tracker = ForegroundAppTracker()
        tracker.resume("first", 100)
        tracker.resume("second", 200)
        tracker.resume("first", 100)
        tracker.pause("first", 110)
        assertEquals("second", tracker.packageName)
        tracker.pause("first", 250)
        assertEquals("second", tracker.packageName)
        tracker.pause("second", 260)
        assertNull(tracker.packageName)
    }
    @Test fun oldActivityPauseCannotClearItsNewActivity() {
        val tracker = ForegroundAppTracker()
        tracker.resume("app", 100, "oldActivity")
        tracker.resume("app", 200, "newActivity")
        tracker.pause("app", 210, "oldActivity")
        assertEquals("app", tracker.packageName)
        tracker.pause("app", 220, "newActivity")
        assertNull(tracker.packageName)
    }
    @Test fun dailyBudgetCountsActivityHandoffWithoutOldPauseEndingNewActivity() {
        val usage = DailyForegroundUsage("app", 0)
        usage.resume("app", 1000, "Old")
        usage.resume("app", 2000, "New")
        usage.pause("app", 2100, "Old")
        usage.pause("app", 10000, "New")
        assertEquals(9000L, usage.totalAt(10000))
    }
    @Test fun dailyBudgetClipsAnIntervalThatBeganBeforeMidnight() {
        val usage = DailyForegroundUsage("app", 5000)
        usage.resume("app", 1000, "Main")
        usage.pause("app", 9000, "Main")
        assertEquals(4000L, usage.totalAt(10000))
    }
    @Test fun dailyBudgetClosesOnAnotherAppAndScreenOff() {
        val usage = DailyForegroundUsage("app", 0)
        usage.resume("app", 1000, "Main")
        usage.resume("other", 2000, "Main")
        usage.resume("app", 4000, "Main")
        usage.screenOff(6000)
        assertEquals(3000L, usage.totalAt(10000))
    }
    @Test fun restartedTrackerRecognizesAnAppResumedMoreThanFiveMinutesAgo() {
        val now = 20 * 60_000L
        val start = AppBlockingPolicy.bootstrapFrom(now)
        assertTrue(start <= now - 10 * 60_000L)
        val tracker = ForegroundAppTracker()
        tracker.resume("app", now - 10 * 60_000L, "Main")
        assertEquals("app", tracker.packageName)
    }
    @Test fun notificationStopCannotBeOverriddenByConfigSync() {
        assertFalse(AppBlockingPolicy.shouldStart(hasRules = true, paused = true,
            visible = true, usageGranted = true, overlayGranted = true))
        assertFalse(AppBlockingPolicy.shouldStart(true, false, false, true, true))
        assertFalse(AppBlockingPolicy.shouldStart(true, false, true, false, true))
        assertFalse(AppBlockingPolicy.shouldStart(true, false, true, true, false))
        assertFalse(AppBlockingPolicy.shouldStart(false, false, true, true, true))
        assertTrue(AppBlockingPolicy.shouldStart(true, false, true, true, true))
    }
}
