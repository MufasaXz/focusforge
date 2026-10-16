package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class YouTubeSurfaceSignalsTest {
    @Test fun retiredStudyFilterCannotBlockAfterUpgradeOrNativeRestart() {
        val legacy = ShieldRules.parse("""{"version":2,"youtube":{"studyOnly":true,"studyChannels":["@teacher"]}}""")
        assertFalse(legacy.youtube.any)
        assertFalse(ShieldStore.encode(legacy).contains("studyOnly"))
        val playback = YouTubeSurfaceSignals()
        playback.observe("com.google.android.youtube:id/watch_player", true)
        assertNull(playback.reason(legacy, 100L, 100L, 0L))
        val shortsRule = legacy.copy(youtube = legacy.youtube.copy(shorts = true))
        assertNull(playback.reason(shortsRule, 100L, 100L, 0L))
        playback.observe("com.google.android.youtube:id/reel_player", true)
        assertNotNull(playback.reason(shortsRule, 100L, 100L, 0L))
    }
    @Test fun completedScanUsesLiveFiltersRatherThanCapturedShortsRule() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/reel_progress_bar", true)
        val captured = ShieldRules.EMPTY.copy(youtube = YoutubeRules(true, false, false))
        assertNotNull(signals.reason(captured, 100L, 100L, 0L))
        val live = captured.copy(youtube = YoutubeRules(false, true, false))
        assertNull(signals.reason(live, 100L, 100L, 0L))
    }
    @Test fun completedScanHonorsNewGraceAndExpiredFocus() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/reel_progress_bar", true)
        val live = ShieldRules.EMPTY.copy(
            youtube = YoutubeRules(true, false, true), focusUntilMillis = 200L,
        )
        assertNotNull(signals.reason(live, 100L, 100L, 0L))
        assertNull(signals.reason(live, 100L, 100L, 150L))
        assertNull(signals.reason(live, 200L, 200L, 0L))
        val allDay = live.copy(youtube = YoutubeRules(true, false, false))
        assertNull(signals.reason(allDay, 1_792_000_000_000L, 100L, 150L))
        assertNotNull(signals.reason(allDay, 1_792_000_000_000L, 150L, 150L))
    }
    @Test fun hiddenShortsPlayerAndCarouselDoNotBlockOrdinaryVideo() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/reel_player", false)
        signals.observe("com.google.android.youtube:id/shorts_shelf", true)
        assertNull(signals.reason(true, false))
    }
    @Test fun visibleProgressBarBlocksShortsInsideTheSameActivity() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/reel_progress_bar", true)
        assertNotNull(signals.reason(true, false))
    }
    @Test fun partialResourceNamesAndOtherPackagesAreNotPlayerEvidence() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/reel_player_thumbnail", true)
        signals.observe("other.package:id/reel_player", true)
        assertNull(signals.reason(true, false))
    }
    @Test fun watchPageKeepsLecturesAvailableButMiniplayerDoesNotBypassFeedRule() {
        val feed = YouTubeSurfaceSignals()
        feed.observe("com.google.android.youtube:id/results", true)
        feed.observe("com.google.android.youtube:id/player_view", true)
        assertNotNull(feed.reason(false, true))
        feed.observe("com.google.android.youtube:id/watch_player", true)
        assertNull(feed.reason(false, true))
    }
}
