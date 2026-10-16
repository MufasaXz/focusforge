package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class YouTubeContentEventTest {
    @Test fun inActivityShortsNavigationTriggersInspection() {
        assertTrue(YouTubeEventPolicy.accepts(2048, 1))
        assertTrue(YouTubeEventPolicy.accepts(2048, 3))
    }
    @Test fun unrelatedTextAndScrollEventsDoNotTriggerTreeWalks() {
        assertFalse(YouTubeEventPolicy.accepts(2048, 2))
        assertFalse(YouTubeEventPolicy.accepts(4096, 1))
        assertFalse(YouTubeEventPolicy.accepts(16, 1))
    }
    @Test fun existingWindowEventsStillTriggerInspection() {
        assertTrue(YouTubeEventPolicy.accepts(32, 0))
        assertTrue(YouTubeEventPolicy.accepts(4194304, 0))
    }
}
