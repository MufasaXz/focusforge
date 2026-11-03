package dev.focusforge.focusforge.shield

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StudyModeTest {
    private val study = ShieldRules.EMPTY.copy(
        youtube = YoutubeRules(
            shorts = false,
            feed = false,
            focusOnly = false,
            study = true,
            studyChannels = listOf("My Physics Teacher", "@calcclub"),
            studyKeywords = listOf("Chemistry"),
        ),
    )

    private fun videoPage(vararg labels: Pair<String?, String?>) = YouTubeSurfaceSignals().apply {
        observe("com.google.android.youtube:id/watch_player", true)
        labels.forEach { (text, description) -> observeText(text, description) }
    }

    @Test fun channelsMatchExactlyByNameOrHandleNeverBySubstring() {
        val policy = StudyChannelPolicy(listOf("My Physics Teacher", "@calcclub"), emptyList())
        assertTrue(policy.allowsChannel("my physics teacher", null))
        assertTrue(policy.allowsChannel(null, "@CalcClub"))
        assertTrue(policy.allowsChannel(null, "calcclub"))
        assertTrue(policy.allowsChannel("Khan Academy", null))
        assertFalse(policy.allowsChannel("My Physics Teacher Reacts", null))
    }

    @Test fun keywordsMatchWholeWordsInTitles() {
        val policy = StudyChannelPolicy(emptyList(), listOf("Chemistry", "ai"))
        assertTrue(policy.allowsTitle(listOf("Organic chemistry in 10 minutes")))
        assertFalse(policy.allowsTitle(listOf("Biochemistry vlog")))
        // Keywords shorter than three letters are ignored.
        assertFalse(policy.allowsTitle(listOf("AI news")))
    }

    @Test fun allowedChannelPlays() {
        val page = videoPage(null to "Subscribe to My Physics Teacher.")
        assertNull(page.reason(study, 100L, 100L, 0L))
    }

    @Test fun subscribedChannelIsReadFromUnsubscribe() {
        val page = videoPage(null to "Unsubscribe from My Physics Teacher.")
        assertNull(page.reason(study, 100L, 100L, 0L))
    }

    @Test fun titleKeywordLetsAnUnlistedChannelPlay() {
        val page = videoPage(
            "Chemistry: bonding explained" to null,
            null to "Subscribe to Random Vlogs.",
        )
        assertNull(page.reason(study, 100L, 100L, 0L))
    }

    @Test fun unlistedChannelPauses() {
        val page = videoPage(
            "Funny moments compilation" to null,
            null to "Subscribe to Random Vlogs.",
        )
        assertEquals("Choose a video from your study channels.", page.reason(study, 100L, 100L, 0L))
    }

    @Test fun handleAloneIdentifiesTheChannel() {
        assertNull(videoPage("@calcclub" to null).reason(study, 100L, 100L, 0L))
        assertNotNull(videoPage("@prankstars" to null).reason(study, 100L, 100L, 0L))
    }

    @Test fun anUnidentifiedPageIsLeftAlone() {
        assertNull(videoPage("Loading" to null).reason(study, 100L, 100L, 0L))
    }

    @Test fun studyModeClosesShortsAndRoundTripsThroughTheWireFormat() {
        val shorts = YouTubeSurfaceSignals().apply {
            observe("com.google.android.youtube:id/reel_player", true)
        }
        assertNotNull(shorts.reason(study, 100L, 100L, 0L))
        val decoded = ShieldRules.parse(ShieldStore.encode(study))
        assertTrue(decoded.youtube.study)
        assertEquals(listOf("My Physics Teacher", "@calcclub"), decoded.youtube.studyChannels)
        assertEquals(listOf("Chemistry"), decoded.youtube.studyKeywords)
    }
}
