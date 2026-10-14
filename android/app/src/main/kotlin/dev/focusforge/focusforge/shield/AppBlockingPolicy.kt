package dev.focusforge.focusforge.shield

import java.util.Calendar

/** Decisions shared by the polling service and native regression tests. */
object AppBlockingPolicy {
    fun reason(packageName: String, rules: ShieldRules, now: Long,
               graceUntil: Long, protected: Set<String>, usedMillis: Long?): String? {
        if (packageName in protected || now < graceUntil) return null
        val rule = rules.ruleFor(packageName) ?: return null
        if (rules.strictModeActive(now)) {
            return "Strict Mode is on. This stays closed until the window ends."
        }
        return when (rule.mode) {
            RuleMode.BLOCK -> "You asked FocusForge to keep this closed."
            RuleMode.FOCUS -> if (rules.focusActive(now)) {
                "This stays closed while you are focusing."
            } else null
            RuleMode.BUDGET -> if (rule.budgetMinutes > 0 && usedMillis != null &&
                usedMillis >= rule.budgetMinutes * 60_000L) {
                "You have used your ${rule.budgetMinutes} minutes for today."
            } else null
        }
    }

    /** Current day plus the previous calendar day covers ongoing sessions across midnight. */
    fun bootstrapFrom(now: Long): Long = Calendar.getInstance().apply {
        timeInMillis = now
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        add(Calendar.DATE, -1)
    }.timeInMillis.coerceAtLeast(0L)

    fun shouldStart(hasRules: Boolean, paused: Boolean, visible: Boolean,
                    usageGranted: Boolean, overlayGranted: Boolean): Boolean =
        hasRules && !paused && visible && usageGranted && overlayGranted
}

/** UsageEvents queries overlap intentionally. Old events cannot undo a newer app transition. */
class ForegroundAppTracker {
    @Volatile var packageName: String? = null
        private set
    private var lastEventAt = Long.MIN_VALUE
    private var activity: String? = null

    fun resume(packageName: String, at: Long, activity: String? = null) {
        if (at < lastEventAt) return
        lastEventAt = at
        this.packageName = packageName
        this.activity = activity
    }

    fun pause(packageName: String, at: Long, activity: String? = null) {
        if (at < lastEventAt) return
        lastEventAt = at
        if (this.packageName == packageName &&
            (this.activity == null || activity == null || this.activity == activity)) {
            this.packageName = null
            this.activity = null
        }
    }

    fun clear(at: Long) {
        packageName = null
        activity = null
        lastEventAt = at
    }
}

/** Activity-aware foreground intervals, clipped to the daily budget boundary. */
class DailyForegroundUsage(private val target: String, private val dayStart: Long) {
    private val foreground = ForegroundAppTracker()
    private var intervalStart: Long? = null
    private var completed = 0L
    private var lastEventAt = Long.MIN_VALUE

    fun resume(pkg: String, at: Long, activity: String? = null) {
        if (at < lastEventAt) return
        lastEventAt = at
        foreground.resume(pkg, at, activity)
        update(at)
    }

    fun pause(pkg: String, at: Long, activity: String? = null) {
        if (at < lastEventAt) return
        lastEventAt = at
        foreground.pause(pkg, at, activity)
        update(at)
    }

    fun screenOff(at: Long) {
        if (at < lastEventAt) return
        lastEventAt = at
        foreground.clear(at)
        update(at)
    }

    private fun update(at: Long) {
        if (foreground.packageName == target) {
            if (intervalStart == null) intervalStart = at.coerceAtLeast(dayStart)
        } else {
            intervalStart?.let { completed += (at - it).coerceAtLeast(0L) }
            intervalStart = null
        }
    }

    fun totalAt(now: Long): Long = completed +
        (intervalStart?.let { (now - it).coerceAtLeast(0L) } ?: 0L)
}

/** Package-only window boundaries; screen contents are inspected only inside YouTube. */
data class ApplicationWindow(val packageName: String, val active: Boolean, val focused: Boolean)

fun foregroundApplication(windows: List<ApplicationWindow>): String? =
    windows.firstOrNull { it.focused }?.packageName
        ?: windows.firstOrNull { it.active }?.packageName
