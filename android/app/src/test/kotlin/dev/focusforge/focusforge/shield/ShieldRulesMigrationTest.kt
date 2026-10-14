package dev.focusforge.focusforge.shield
import org.junit.Assert.*
import org.junit.Test

class ShieldRulesMigrationTest {
    @Test fun oldMergedPayloadIsRejectedBeforeFlutterStarts() {
        val old = """{"apps":{"com.instagram.android":{"label":"Instagram","mode":"block"}},"youtube":{"shorts":true}}"""
        assertTrue(ShieldRules.parse(old).apps.isEmpty())
        assertFalse(ShieldRules.parse(old).youtube.any)
    }
    @Test fun currentSelfSelectedPayloadSurvivesNativeRoundTrip() {
        val raw = """{"version":2,"apps":{"com.instagram.android":{"label":"Instagram","mode":"focus"}},"youtube":{"feed":true},"focusUntil":2000000000000}"""
        val rules = ShieldRules.parse(raw)
        assertEquals(RuleMode.FOCUS, rules.ruleFor("com.instagram.android")?.mode)
        assertTrue(rules.youtube.feed)
        assertEquals(rules, ShieldRules.parse(ShieldStore.encode(rules)))
    }
}
