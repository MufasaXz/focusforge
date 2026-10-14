package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class YouTubeWindowBoundaryTest {
    @Test fun applicationBehindAnOverlayRemainsTheForeground() {
        assertEquals("youtube", foregroundApplication(listOf(
            ApplicationWindow("youtube", active = true, focused = false),
        )))
    }
    @Test fun homeAndSettingsReplaceTheCoveredApplication() {
        assertEquals("settings", foregroundApplication(listOf(
            ApplicationWindow("youtube", false, false),
            ApplicationWindow("settings", true, true),
        )))
        assertEquals("home", foregroundApplication(listOf(ApplicationWindow("home", true, false))))
    }
    @Test fun ownApplicationIsNotConfusedWithItsOverlay() {
        assertEquals("focusforge", foregroundApplication(listOf(ApplicationWindow("focusforge", true, true))))
    }
    @Test fun unknownOrUnfocusedWindowsAreNotEvidenceOfAStillOpenYoutube() {
        assertNull(foregroundApplication(emptyList()))
        assertNull(foregroundApplication(listOf(ApplicationWindow("youtube", false, false))))
    }
}
