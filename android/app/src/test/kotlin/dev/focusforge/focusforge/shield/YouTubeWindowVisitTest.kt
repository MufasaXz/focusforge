package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class YouTubeWindowVisitTest {
    @Test fun returningFromRecentsGetsItsOwnInspectionAndLoadingRetry() {
        val visit = YouTubeWindowVisit(350)
        assertTrue(visit.shouldInspect("youtube", 1000))
        assertTrue(visit.claimLoadingRetry("youtube"))
        assertFalse(visit.claimLoadingRetry("youtube"))
        visit.end()
        // The launcher cannot clear the debounce: service events are YouTube-only.
        assertTrue(visit.shouldInspect("youtube", 1100))
        assertTrue(visit.claimLoadingRetry("youtube"))
    }

    @Test fun eventsWithinTheSameVisitStayDebouncedAndCannotPollForever() {
        val visit = YouTubeWindowVisit(350)
        assertTrue(visit.shouldInspect("youtube", 1000))
        assertFalse(visit.shouldInspect("youtube", 1100))
        assertTrue(visit.shouldInspect("youtube", 1400))
        assertTrue(visit.claimLoadingRetry("youtube"))
        assertFalse(visit.claimLoadingRetry("youtube"))
    }
}
