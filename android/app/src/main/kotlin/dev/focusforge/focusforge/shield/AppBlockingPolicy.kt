package dev.focusforge.focusforge.shield

import java.util.Calendar

/**
 * What a usage event means to a foreground tracker.
 *
 * Shared because the detector and the budget counter each used to carry their
 * own copy of this mapping, and they drifted: the budget counter never learned
 * that an activity can stop without pausing, so its interval stayed open and
 * the day's total kept climbing while the user was in another app entirely.
 * One mapping, one place to add an event type.
 */
enum class UsageAction { RESUME, PAUSE, SCREEN_OFF, SCREEN_ON }

/** Decisions shared by the polling service and native regression tests. */
object AppBlockingPolicy {
    /**
     * The event types that move an app in or out of the foreground.
     *
     * Raw constants rather than `UsageEvents.Event`, so this object stays free
     * of Android and reachable from a plain JVM test. The values are frozen
     * API: `ACTIVITY_RESUMED` is `MOVE_TO_FOREGROUND` renamed, and the same
     * integer, as are the other two.
     */
    private const val RESUMED = 1
    private const val PAUSED = 2
    private const val SCREEN_INTERACTIVE = 15
    private const val SCREEN_NON_INTERACTIVE = 16

    /** Not every app raises a pause on the way out; a stop ends the session too. */
    private const val STOPPED = 23

    fun actionFor(eventType: Int): UsageAction? = when (eventType) {
        RESUMED -> UsageAction.RESUME
        PAUSED, STOPPED -> UsageAction.PAUSE
        SCREEN_NON_INTERACTIVE -> UsageAction.SCREEN_OFF
        SCREEN_INTERACTIVE -> UsageAction.SCREEN_ON
        else -> null
    }

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
            return "Paused until Strict Mode ends."
        }
        return when (rule.mode) {
            RuleMode.BLOCK -> "You chose to pause this app."
            RuleMode.FOCUS -> if (rules.focusActive(now)) {
                "Paused during your focus session."
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
    // Multi-resume and transient Overview can leave the underlying activity
    // resumed. Retain only activities with no matching pause, in a bounded set.
    private val resumed = LinkedHashMap<Pair<String, String?>, Long>()
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
        resumed[packageName to activity] = at
        while (resumed.size > 32) {
            resumed.remove(resumed.minByOrNull { it.value }!!.key)
        }
        this.packageName = packageName
        this.activity = activity
    }

    fun pause(packageName: String, at: Long, activity: String? = null) {
        if (at < screenBoundaryAt) return
        val key = packageName to activity
        stoppedAt[key] = maxOf(stoppedAt[key] ?: Long.MIN_VALUE, at)
        resumed.entries.removeAll { (candidate, resumedAt) ->
            candidate.first == packageName && resumedAt <= at &&
                (candidate.second == null || activity == null || candidate.second == activity)
        }
        lastEventAt = maxOf(lastEventAt, at)
        if (suspendedPackage == packageName &&
            (suspendedActivity == null || activity == null || suspendedActivity == activity)) {
            suspendedPackage = null
            suspendedActivity = null
        }
        if (this.packageName == packageName &&
            at >= lastResumeAt &&
            (this.activity == null || activity == null || this.activity == activity)) {
            val underlying = resumed.maxByOrNull { it.value }?.key
            this.packageName = underlying?.first
            this.activity = underlying?.second
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
        resumed.clear()
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
        resumed.clear()
        lastEventAt = at
    }

    fun screenOn(at: Long) {
        if (at < lastEventAt) return
        screenBoundaryAt = at
        if (packageName == null) {
            packageName = suspendedPackage
            activity = suspendedActivity
            packageName?.let { resumed[it to activity] = at }
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
