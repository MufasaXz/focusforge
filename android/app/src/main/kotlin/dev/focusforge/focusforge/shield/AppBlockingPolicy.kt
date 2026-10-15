package dev.focusforge.focusforge.shield

import java.util.Calendar

/** Decisions shared by the polling service and native regression tests. */
object AppBlockingPolicy {
    /** A pause alone is not evidence that a different app is in front.
     * Preserve an existing cover until a resume identifies the next app.
     * Explicit permission revocation, screen lock, Stop and grace release it separately.
     */
    fun overlayTarget(foreground: String?, covered: String?): String? = foreground ?: covered

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

    fun foregroundQueryStart(lastQueryAt: Long, now: Long, replay: Boolean): Long =
        if (replay || lastQueryAt > now) bootstrapFrom(now)
        // UsageEvents can publish task resumes late, especially from Overview.
        // Replay a small bounded window; the tracker ignores older timestamps.
        else (lastQueryAt - 5_000L).coerceAtLeast(0L)

    fun cachedUsage(sample: Long?, sampledAt: Long, now: Long, foreground: Boolean): Long? =
        if (now - sampledAt in 0L until 10_000L)
            sample?.let { it + if (foreground) now - sampledAt else 0L }
        else null
}

/** UsageEvents queries overlap intentionally. Old events cannot undo a newer app transition. */
class ForegroundAppTracker {
    @Volatile var packageName: String? = null
        private set
    private var lastEventAt = Long.MIN_VALUE
    private var lastResumeAt = Long.MIN_VALUE
    private var screenBoundaryAt = Long.MIN_VALUE
    private val stoppedAt = HashMap<Pair<String, String?>, Long>()
    private var activity: String? = null
    private var suspendedPackage: String? = null
    private var suspendedActivity: String? = null

    fun resume(packageName: String, at: Long, activity: String? = null) {
        // A different activity can stop after the new one resumes. OEMs may
        // publish that stop first; it must not fence out the delayed resume.
        if (at < lastResumeAt || at < screenBoundaryAt ||
            at <= (stoppedAt[packageName to activity] ?: Long.MIN_VALUE) ||
            at <= (stoppedAt[packageName to null] ?: Long.MIN_VALUE)) return
        lastResumeAt = at
        lastEventAt = maxOf(lastEventAt, at)
        stoppedAt.entries.removeAll { it.value < at }
        suspendedPackage = null
        suspendedActivity = null
        this.packageName = packageName
        this.activity = activity
    }

    fun pause(packageName: String, at: Long, activity: String? = null) {
        if (at < lastResumeAt || at < screenBoundaryAt) return
        val key = packageName to activity
        stoppedAt[key] = maxOf(stoppedAt[key] ?: Long.MIN_VALUE, at)
        lastEventAt = maxOf(lastEventAt, at)
        if (suspendedPackage == packageName &&
            (suspendedActivity == null || activity == null || suspendedActivity == activity)) {
            suspendedPackage = null
            suspendedActivity = null
        }
        if (this.packageName == packageName &&
            (this.activity == null || activity == null || this.activity == activity)) {
            this.packageName = null
            this.activity = null
        }
    }

    fun clear(at: Long) {
        packageName = null
        activity = null
        suspendedPackage = null
        suspendedActivity = null
        lastEventAt = at
        lastResumeAt = at
        screenBoundaryAt = at
        stoppedAt.clear()
    }

    fun screenOff(at: Long) {
        if (at < lastEventAt) return
        screenBoundaryAt = at
        if (packageName != null) {
            suspendedPackage = packageName
            suspendedActivity = activity
        }
        packageName = null
        activity = null
        lastEventAt = at
    }

    fun screenOn(at: Long) {
        if (at < lastEventAt) return
        screenBoundaryAt = at
        if (packageName == null) {
            packageName = suspendedPackage
            activity = suspendedActivity
        }
        suspendedPackage = null
        suspendedActivity = null
        lastEventAt = at
    }

    fun reset() { clear(Long.MIN_VALUE) }
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
        foreground.screenOff(at)
        update(at)
    }

    fun screenOn(at: Long) {
        if (at < lastEventAt) return
        lastEventAt = at
        foreground.screenOn(at)
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
