package dev.focusforge.focusforge.shield

import org.junit.Assert.*
import org.junit.Test

class StudyChannelPolicyTest {
    @Test fun studyChannelConfigurationSurvivesNativePersistence() {
        val raw = """{"version":2,"youtube":{"studyOnly":true,"studyChannels":["@teacher","Open Science"]}}"""
        val rules = ShieldRules.parse(raw)
        assertTrue(rules.youtube.any)
        assertTrue(rules.youtube.studyOnly)
        assertEquals(listOf("@teacher", "Open Science"), rules.youtube.studyChannels)
        assertEquals(rules, ShieldRules.parse(ShieldStore.encode(rules)))
        val malformed = ShieldRules.parse("""{"version":2,"youtube":{"studyOnly":true,"studyChannels":[42,null,{},""]}}""")
        assertTrue(malformed.youtube.studyChannels.isEmpty())
    }

    @Test fun acceptsOnlyExactSelectedCreatorIdentity() {
        val policy = StudyChannelPolicy(listOf(" @MathTeacher ", "Open Science"))
        assertTrue(policy.allows(listOf("@matHTeacher")))
        assertTrue(policy.allows(listOf("Open   Science")))
        assertFalse(policy.allows(listOf("Open Science Highlights")))
        assertFalse(policy.allows(listOf("MathTeacher")))
        assertFalse(policy.allows(emptyList()))
    }

    @Test fun ignoresTitlesHiddenNodesAndOtherPackageLabels() {
        val rules = ShieldRules.EMPTY.copy(
            youtube = YoutubeRules(false, false, false, studyOnly = true, studyChannels = listOf("@teacher")),
        )
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/watch_player", true)
        signals.observe("com.google.android.youtube:id/title", true, "@teacher")
        signals.observe("com.google.android.youtube:id/channel_name", false, "@teacher")
        signals.observe("other.app:id/channel_name", true, "@teacher")
        assertNotNull(signals.reason(rules, 100L, 100L, 0L))
        signals.observe("com.google.android.youtube:id/channel_name", true, "@teacher")
        assertNotNull(signals.reason(rules, 100L, 100L, 0L))
        signals.observe("com.google.android.youtube:id/channel_name", true, "@teacher", true)
        assertNull(signals.reason(rules, 100L, 100L, 0L))
    }

    @Test fun appliesNewStudyListAtDecisionTimeAndKeepsShortsPriority() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/watch_player", true)
        signals.observe("com.google.android.youtube:id/channel_handle", true, "@teacher", true)
        val rules = ShieldRules.EMPTY.copy(
            youtube = YoutubeRules(false, false, false, studyOnly = true, studyChannels = listOf("@teacher")),
        )
        assertNull(signals.reason(rules, 100L, 100L, 0L))
        assertNotNull(signals.reason(rules.copy(youtube = rules.youtube.copy(studyChannels = emptyList())), 100L, 100L, 0L))
        signals.observe("com.google.android.youtube:id/reel_player", true)
        assertEquals("Shorts are paused. Keep your focus.", signals.reason(rules.copy(youtube = rules.youtube.copy(shorts = true)), 100L, 100L, 0L))
    }

    @Test fun browsingGraceAndExpiredFocusKeepExistingBehavior() {
        val signals = YouTubeSurfaceSignals()
        signals.observe("com.google.android.youtube:id/results", true)
        val rules = ShieldRules.EMPTY.copy(
            youtube = YoutubeRules(false, false, true, studyOnly = true), focusUntilMillis = 200L,
        )
        assertNull(signals.reason(rules, 100L, 100L, 0L))
        signals.observe("com.google.android.youtube:id/watch_player", true)
        assertNotNull(signals.reason(rules, 100L, 100L, 0L))
        assertNull(signals.reason(rules, 100L, 100L, 150L))
        assertNull(signals.reason(rules, 200L, 200L, 0L))
    }
}
