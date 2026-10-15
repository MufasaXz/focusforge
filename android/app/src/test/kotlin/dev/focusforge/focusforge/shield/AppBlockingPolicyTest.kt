package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class AppBlockingPolicyTest {
    @Test fun delayedTaskResumeSurvivesALaterLauncherStop() {
        val tracker = ForegroundAppTracker()
        tracker.resume("launcher",100,"Overview")
        tracker.pause("launcher",300,"Overview")
        // The launcher stop can be published before the earlier app resume.
        tracker.resume("blocked",250,"Main")
        assertEquals("blocked",tracker.packageName)
        tracker.pause("launcher",300,"Overview")
        assertEquals("blocked",tracker.packageName)
    }
    @Test fun delayedNewActivityResumeSurvivesOldActivityStop() {
        val tracker = ForegroundAppTracker()
        tracker.resume("blocked",100,"Old")
        tracker.pause("blocked",300,"Old")
        tracker.resume("blocked",250,"New")
        assertEquals("blocked",tracker.packageName)
        tracker.pause("blocked",300,"Old")
        assertEquals("blocked",tracker.packageName)
        tracker.pause("blocked",400,"New")
        tracker.resume("blocked",250,"New")
        assertNull(tracker.packageName)
    }
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
    @Test fun unlockingReplaysForegroundHistoryWhenNoNewResumeEventExists() {
        val now = 20 * 60_000L
        val queryStart = AppBlockingPolicy.foregroundQueryStart(now - 400, now, true)
        assertTrue(queryStart <= now - 10 * 60_000L)
        val tracker = ForegroundAppTracker()
        tracker.clear(now - 1000)
        tracker.resume("app", now - 10 * 60_000L, "Main")
        assertNull(tracker.packageName)
        // A fresh replay must not retain the pre-unlock timestamp fence.
        tracker.reset()
        tracker.resume("app", now - 10 * 60_000L, "Main")
        tracker.screenOff(now - 1000L)
        assertNull(tracker.packageName)
        tracker.screenOn(now)
        assertEquals("app", tracker.packageName)
    }
    @Test fun anActivityPauseWhileScreenIsOffPreventsStaleRestoration() {
        val tracker = ForegroundAppTracker()
        tracker.resume("app", 100, "Main")
        tracker.screenOff(200)
        tracker.pause("app", 250, "Main")
        tracker.screenOn(300)
        assertNull(tracker.packageName)
        tracker.resume("app", 400, "Main")
        tracker.screenOff(500)
        tracker.resume("other", 600, "Main")
        tracker.screenOn(700)
        assertEquals("other", tracker.packageName)
    }
    @Test fun aBackwardClockChangeDoesNotLeaveTheQueryWindowInTheFuture() {
        val now = 20 * 60_000L
        val queryStart = AppBlockingPolicy.foregroundQueryStart(now + 60_000L, now, false)
        assertTrue(queryStart <= now - 10 * 60_000L)
        assertEquals(now - 5_400L, AppBlockingPolicy.foregroundQueryStart(now - 400L, now, false))
    }
    @Test fun delayedRecentsResumeRemainsInsideTheNextQueryWindow() {
        val now = 20 * 60_000L
        // Some Android builds publish a resume after its timestamp. A short
        // overlap skips it forever once the high-water mark has advanced.
        val resumedAt = now - 2_000L
        val start = AppBlockingPolicy.foregroundQueryStart(now - 120L, now, false)
        assertTrue(start <= resumedAt)
        val tracker = ForegroundAppTracker()
        tracker.resume("launcher", now - 3_000L, "Overview")
        if (resumedAt >= start) tracker.resume(packageName, resumedAt, "Main")
        assertEquals(packageName, tracker.packageName)
    }
    @Test fun budgetCacheRejectsNegativeAgeAndExpiredSamples() {
        assertNull(AppBlockingPolicy.cachedUsage(1_800_000L, 10_000L, 9_000L, true))
        assertNull(AppBlockingPolicy.cachedUsage(1_800_000L, 10_000L, 20_000L, true))
        assertEquals(1_809_999L, AppBlockingPolicy.cachedUsage(1_800_000L, 10_000L, 19_999L, true))
        assertEquals(1_800_000L, AppBlockingPolicy.cachedUsage(1_800_000L, 10_000L, 19_999L, false))
    }
    @Test fun aTransientPauseDoesNotDropTheExistingBlock() {
        assertEquals(packageName, AppBlockingPolicy.overlayTarget(null, packageName))
        assertEquals(packageName, AppBlockingPolicy.overlayTarget(packageName, packageName))
        assertNull(AppBlockingPolicy.overlayTarget(null, null))
    }
    @Test fun aConfirmedAppSwitchReleasesTheOldCoverIncludingHomeAndSettings() {
        assertEquals("launcher", AppBlockingPolicy.overlayTarget("launcher", packageName))
        assertEquals("settings", AppBlockingPolicy.overlayTarget("settings", packageName))
        assertNull(AppBlockingPolicy.reason("settings", rules(), 1000, 0, setOf("settings"), null))
    }
    @Test fun dailyBudgetRestoresAfterUnlockWithoutCountingLockedTime() {
        val usage = DailyForegroundUsage("app", 0)
        usage.resume("app", 1000, "Main")
        usage.screenOff(2000)
        usage.screenOn(6000)
        assertEquals(4000L, usage.totalAt(9000))
        usage.pause("app", 10000, "Main")
        assertEquals(5000L, usage.totalAt(20000))
    }
}
