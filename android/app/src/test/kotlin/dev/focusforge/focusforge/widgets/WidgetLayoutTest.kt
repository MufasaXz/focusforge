package dev.focusforge.focusforge.widgets

import org.junit.Assert.*
import org.junit.Test

class WidgetLayoutTest {
    @Test fun weeklyLayoutPreservesAChartAndFittingHeadlineAtTwiceTextScale() {
        for ((width, height, scale) in listOf(Triple(140, 140, 2f), Triple(180, 180, 1f), Triple(280, 180, 2f), Triple(320, 320, 2f))) {
            val layout = WeeklyWidgetLayout.forWidget(width, height, scale, "123h 45m")
            assertTrue(layout.chartHeightDp >= 20f)
            assertTrue(layout.contentHeightDp <= height - 2 * layout.paddingDp + 0.1f)
            assertTrue(layout.headlineSp * scale * 8 * 0.62f <= width - 2 * layout.paddingDp + 0.1f)
        }
    }

    @Test fun studyLayoutFitsLongCountdownAndHidesAuxiliaryLabelsBeforePrimaryValue() {
        val small = StudyWidgetLayout.forWidget(140, 140, 2f, 7)
        assertFalse(small.showCaption)
        assertFalse(small.showProgress)
        assertTrue(small.contentHeightDp <= 116f)
        assertTrue(small.countdownSp * 2 * 7 * .62f <= 116f)
        val large = StudyWidgetLayout.forWidget(320, 320, 1f, 5)
        assertTrue(large.showSubject)
        assertTrue(large.showProgress)
        assertTrue(large.showCaption)
    }
}
