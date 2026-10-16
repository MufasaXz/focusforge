package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class ForegroundRecoveryTest {
    @Test fun overviewCloseRestoresOnlyAnActivityWithNoPauseAndRejectsReplay() {
        val tracker = ForegroundAppTracker()
        tracker.resume("app", 100, "Main")
        tracker.resume("home", 200, "Overview")
        tracker.pause("home", 300, "Overview")
        assertEquals("app", tracker.packageName)
        tracker.resume("home", 200, "Overview")
        tracker.pause("home", 300, "Overview")
        assertEquals("app", tracker.packageName)
        tracker.pause("app", 350, "Main")
        assertNull(tracker.packageName)
    }
    @Test fun pausedUnderlyingActivityCannotBeRestoredAfterOverview() {
        val tracker = ForegroundAppTracker()
        tracker.resume("app", 100, "Main")
        tracker.resume("home", 200, "Overview")
        tracker.pause("app", 250, "Main")
        tracker.pause("home", 300, "Overview")
        assertNull(tracker.packageName)
    }
    @Test fun screenBoundaryDiscardsOldUnderlyingCandidates() {
        val tracker = ForegroundAppTracker()
        tracker.resume("old", 100, "Main")
        tracker.resume("latest", 200, "Main")
        tracker.screenOff(300)
        tracker.screenOn(400)
        assertEquals("latest", tracker.packageName)
        tracker.pause("latest", 500, "Main")
        assertNull(tracker.packageName)
    }
}
