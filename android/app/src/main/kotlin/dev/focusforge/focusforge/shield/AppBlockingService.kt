package dev.focusforge.focusforge.shield

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.*
import android.provider.Settings
import android.view.*
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import dev.focusforge.focusforge.MainActivity
import dev.focusforge.focusforge.R
import java.util.Calendar

/**
 * User-started local app boundaries. Usage access detects foreground activity;
 * draw-over-app permission displays the pause. Accessibility is never consulted.
 * No boot receiver or background-start exemption: starts originate in visible UI.
 */
@Suppress("DEPRECATION")
class AppBlockingService : Service() {
    companion object {
        private const val CHANNEL = "focusforge_app_boundaries"
        private const val NOTIFICATION_ID = 4702
        private const val ACTION_STOP = "dev.focusforge.STOP_APP_BOUNDARIES"
        private const val PREFS = "focusforge_shield"
        private const val PAUSED = "app_blocking_paused"
        private const val POLL_MS = 400L
        @Volatile var instance: AppBlockingService? = null
            private set
        @Volatile var activityVisible = false

        fun hasUsageAccess(context: Context): Boolean = try {
            val ops = context.getSystemService(APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName,
            ) else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) { false }

        fun overlayAllowed(context: Context): Boolean = Settings.canDrawOverlays(context)
        fun isPaused(context: Context): Boolean = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            .getBoolean(PAUSED, false)

        /** Config sync never clears the explicit notification Stop latch. */
        fun sync(context: Context): Boolean {
            val rules = ShieldStore.load(context)
            if (rules.apps.isEmpty() || !hasUsageAccess(context) || !overlayAllowed(context) || isPaused(context)) {
                instance?.stopSelf()
                return false
            }
            if (instance != null) return true
            if (!AppBlockingPolicy.shouldStart(true, isPaused(context), activityVisible,
                    hasUsageAccess(context), overlayAllowed(context))) return false
            return try {
                val intent = Intent(context, AppBlockingService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
                true
            } catch (_: RuntimeException) { false }
        }

        fun pauseFromUser(context: Context) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(PAUSED, true).apply()
            instance?.stopSelf()
        }

        /** Called only while the user enables a rule or restores missing app access. */
        fun resumeFromUser(context: Context): Boolean {
            if (!activityVisible || !hasUsageAccess(context) || !overlayAllowed(context)) return false
            context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(PAUSED, false).apply()
            // First rule is saved immediately after this grant check.
            return if (ShieldStore.load(context).apps.isEmpty()) true else sync(context)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var worker: HandlerThread
    private lateinit var detector: Handler
    private lateinit var windows: WindowManager
    private val foreground = ForegroundAppTracker()
    private val graceUntil = HashMap<String, Long>()
    private var lastQueryAt = 0L
    private var overlay: View? = null
    private var covered: String? = null
    private var coveredReason: String? = null
    private var suppressUntil = 0L
    @Volatile private var protected = emptySet<String>()
    private var lastProtectionCheck = 0L
    private var budgetPackage: String? = null
    private var budgetSampleAt = 0L
    private var budgetSample: Long? = null

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        windows = getSystemService(WINDOW_SERVICE) as WindowManager
        worker = HandlerThread("ff-app-boundaries").apply { start() }
        detector = Handler(worker.looper)
        protected = FocusAccessibilityService.protectedPackages(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            pauseFromUser(this)
            stopSelf()
            return START_NOT_STICKY
        }
        if (isPaused(this) || !hasUsageAccess(this) || !overlayAllowed(this) ||
            ShieldStore.load(this).apps.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (instance === this) return START_STICKY
        try {
            val notification = notification()
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else startForeground(NOTIFICATION_ID, notification)
        } catch (_: RuntimeException) {
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        detector.removeCallbacks(poll)
        lastQueryAt = AppBlockingPolicy.bootstrapFrom(System.currentTimeMillis())
        detector.post(poll)
        return START_STICKY
    }

    private fun notification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "App boundaries", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Visible while your selected apps are being paused. Stop pauses app boundaries."
                setShowBadge(false)
            },
        )
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 4702, Intent(this, MainActivity::class.java), flags)
        val stop = PendingIntent.getService(this, 4703,
            Intent(this, AppBlockingService::class.java).setAction(ACTION_STOP), flags)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else Notification.Builder(this)
        return builder.setSmallIcon(R.drawable.ic_focus_live)
            .setContentTitle("FocusForge app boundaries are active")
            .setContentText("Your chosen apps are paused on this device. Tap Stop to pause boundaries.")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
    }

    private val poll = object : Runnable {
        override fun run() {
            if (instance !== this@AppBlockingService) return
            val now = System.currentTimeMillis()
            if (!hasUsageAccess(this@AppBlockingService) || !overlayAllowed(this@AppBlockingService) ||
                isPaused(this@AppBlockingService)) {
                main.post { dismissOverlay(); stopSelf() }
                return
            }
            val rules = ShieldStore.load(this@AppBlockingService)
            if (rules.apps.isEmpty()) { main.post { stopSelf() }; return }
            val power = getSystemService(POWER_SERVICE) as PowerManager
            val lock = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            if (!power.isInteractive || lock.isKeyguardLocked) {
                foreground.clear(now)
                lastQueryAt = now
                main.post { dismissOverlay() }
                detector.postDelayed(this, 1500L)
                return
            }
            if (now - lastProtectionCheck > 30_000L) {
                protected = FocusAccessibilityService.protectedPackages(this@AppBlockingService)
                lastProtectionCheck = now
            }
            val previousFront = foreground.packageName
            readForeground(now)
            if (previousFront != foreground.packageName) { budgetPackage = null; budgetSample = null }
            val front = foreground.packageName
            val used = if (front != null && rules.ruleFor(front)?.mode == RuleMode.BUDGET)
                usedToday(front, now) else null
            val reason = front?.let {
                AppBlockingPolicy.reason(it, rules, now, graceUntil[it] ?: 0L, protected, used)
            }
            main.post {
                if (instance !== this@AppBlockingService) return@post
                // Snapshots cannot cover a different app after a newer poll or a button action.
                if (front != foreground.packageName || now < suppressUntil) return@post
                if (front == null || reason == null) dismissOverlay()
                else if (covered != front || coveredReason != reason || overlay?.isAttachedToWindow != true) {
                    showOverlay(front, reason)
                }
            }
            detector.postDelayed(this, POLL_MS)
        }
    }

    private fun readForeground(now: Long) {
        val manager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        try {
            val events = manager.queryEvents((lastQueryAt - 500L).coerceAtLeast(0), now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val pkg = event.packageName.orEmpty()
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> if (pkg.isNotEmpty()) foreground.resume(pkg, event.timeStamp, event.className)
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> if (pkg.isNotEmpty()) foreground.pause(pkg, event.timeStamp, event.className)
                    UsageEvents.Event.SCREEN_NON_INTERACTIVE -> foreground.clear(event.timeStamp)
                }
            }
            lastQueryAt = now
        } catch (_: RuntimeException) {
            foreground.clear(now) // Failure is not evidence that an app is still in front.
            lastQueryAt = now
        }
    }

    /** Event-derived daily foreground time includes the currently running interval. */
    private fun usedToday(pkg: String, now: Long): Long? {
        if (budgetPackage == pkg && now - budgetSampleAt < 10_000L) return budgetSample?.let {
            it + if (foreground.packageName == pkg) now - budgetSampleAt else 0L
        }
        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val manager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        return try {
            val events = manager.queryEvents(AppBlockingPolicy.bootstrapFrom(now), now)
            val event = UsageEvents.Event()
            val usage = DailyForegroundUsage(pkg, midnight)
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val eventPackage = event.packageName.orEmpty()
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> if (eventPackage.isNotEmpty()) {
                        usage.resume(eventPackage, event.timeStamp, event.className)
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> if (eventPackage.isNotEmpty()) {
                        usage.pause(eventPackage, event.timeStamp, event.className)
                    }
                    UsageEvents.Event.SCREEN_NON_INTERACTIVE -> usage.screenOff(event.timeStamp)
                }
            }
            val total = usage.totalAt(now)
            budgetPackage = pkg; budgetSampleAt = now; budgetSample = total
            total
        } catch (_: RuntimeException) { null }
    }

    fun grantGrace(pkg: String, seconds: Int) {
        // Both writes and reads on detector; dismiss immediately on main.
        detector.post { graceUntil[pkg] = System.currentTimeMillis() + seconds.coerceIn(5, 600) * 1000L }
        suppressUntil = System.currentTimeMillis() + 500L
        if (covered == pkg) dismissOverlay()
    }

    fun isCovering(pkg: String): Boolean = covered == pkg

    private fun showOverlay(pkg: String, reason: String) {
        if (!overlayAllowed(this) || !hasUsageAccess(this) || pkg in protected ||
            foreground.packageName != pkg) return
        dismissOverlay()
        // A whole-app rule takes precedence over a YouTube-surface rule.
        FocusAccessibilityService.instance?.dismissForAppBoundary(pkg)
        val view = LayoutInflater.from(this).inflate(R.layout.ff_block_overlay, null)
        val label = ShieldStore.load(this).ruleFor(pkg)?.label ?: pkg
        try { view.findViewById<ImageView>(R.id.ff_block_icon).setImageDrawable(packageManager.getApplicationIcon(pkg)) }
        catch (_: Exception) { }
        view.findViewById<TextView>(R.id.ff_block_app).text = label
        view.findViewById<TextView>(R.id.ff_block_reason).text = reason
        view.findViewById<TextView>(R.id.ff_block_note).text =
            "Leave this app closed, or take three slow breaths before deciding to open it."
        view.findViewById<Button>(R.id.ff_block_back).setOnClickListener {
            suppressUntil = System.currentTimeMillis() + 1200L
            dismissOverlay()
            ShieldEvents.emit(pkg, label, ShieldEvents.WALKED_AWAY)
            try { startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) { }
        }
        view.findViewById<Button>(R.id.ff_block_anyway).setOnClickListener {
            suppressUntil = System.currentTimeMillis() + 1200L
            dismissOverlay()
            try {
                startActivity(Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    .putExtra(FocusAccessibilityService.EXTRA_BLOCKED_PACKAGE, pkg)
                    .putExtra(FocusAccessibilityService.EXTRA_BLOCKED_LABEL, label)
                    .putExtra(FocusAccessibilityService.EXTRA_GRACE_SECONDS, ShieldStore.load(this).graceSeconds))
            } catch (_: Exception) {
                ShieldEvents.emit(pkg, label, ShieldEvents.OPENED_ANYWAY)
                grantGrace(pkg, ShieldStore.load(this).graceSeconds)
            }
        }
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else { @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE }
        val params = WindowManager.LayoutParams(WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT, type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.START }
        try {
            windows.addView(view, params)
            overlay = view; covered = pkg; coveredReason = reason
            val content = view.findViewById<View>(R.id.ff_block_content)
            applyTypeface(content)
            if (Settings.Global.getFloat(content.context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f) {
                content.alpha = 0f; content.translationY = 16f * resources.displayMetrics.density
                content.animate().alpha(1f).translationY(0f).setDuration(300)
                    .setInterpolator(DecelerateInterpolator()).start()
            }
        } catch (_: RuntimeException) { dismissOverlay(); stopSelf() }
    }

    private fun applyTypeface(view: View) {
        val regular = try { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Inter-Regular.ttf") }
            catch (_: Exception) { Typeface.create("sans-serif", Typeface.NORMAL) }
        val bold = try { Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/InterDisplay-SemiBold.ttf") }
            catch (_: Exception) { Typeface.create("sans-serif", Typeface.BOLD) }
        fun apply(child: View) {
            if (child is TextView) child.typeface = if (child.typeface?.isBold == true) bold else regular
            if (child is ViewGroup) for (i in 0 until child.childCount) apply(child.getChildAt(i))
        }
        apply(view)
    }

    private fun dismissOverlay() {
        val view = overlay
        overlay = null; covered = null; coveredReason = null
        view?.findViewById<View>(R.id.ff_block_content)?.animate()?.cancel()
        if (view != null) try { windows.removeView(view) } catch (_: RuntimeException) { }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        detector.removeCallbacksAndMessages(null)
        worker.quitSafely()
        dismissOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
