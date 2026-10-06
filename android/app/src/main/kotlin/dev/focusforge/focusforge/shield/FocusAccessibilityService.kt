package dev.focusforge.focusforge.shield

import android.accessibilityservice.AccessibilityService
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import dev.focusforge.focusforge.R
import java.util.Calendar

/**
 * Keeps the apps the user chose closed.
 *
 * This runs natively rather than through the Flutter engine on purpose. An
 * accessibility service is restarted by the system after a process kill and
 * can be woken with no UI attached; a block screen that has to wait for a Dart
 * isolate to boot would either miss the launch or arrive after the user is
 * already scrolling. It reads its rules from [ShieldStore] and draws its own
 * window, so it is fully self-contained.
 *
 * What it observes is deliberately narrow: the package name that came to the
 * foreground. It reads on-screen content in exactly one case — to tell the
 * YouTube Shorts player from a normal video — and never stores what it reads.
 */
class FocusAccessibilityService : AccessibilityService() {

    companion object {
        private const val DEBOUNCE_MS = 350L
        private const val FALLBACK_HOME_DELAY_MS = 700L

        /** Bound on the YouTube window walk, so a deep tree cannot stall the
         *  launch path it is running on. */
        private const val MAX_NODES = 400

        private const val YOUTUBE = "com.google.android.youtube"

        /** Extras the service puts on the intent it sends to [MainActivity]. */
        const val EXTRA_BLOCKED_PACKAGE = "ff.blocked.package"
        const val EXTRA_BLOCKED_LABEL = "ff.blocked.label"
        const val EXTRA_GRACE_SECONDS = "ff.blocked.grace"

        /** The live instance, or null while the service is not connected. */
        @Volatile
        var instance: FocusAccessibilityService? = null
            private set

        /**
         * True when the user has enabled this service in Android's settings.
         *
         * Checked by reading the same secure setting Android writes, which is
         * the only way to know without binding to the service. It matches on
         * the component name, so it answers "is *this* service on", not "is
         * any accessibility service on".
         */
        fun isEnabled(context: Context): Boolean {
            val enabled = try {
                Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED,
                )
            } catch (_: Settings.SettingNotFoundException) {
                return false
            }
            if (enabled != 1) return false

            val component = "${context.packageName}/${
                FocusAccessibilityService::class.java.canonicalName
            }"
            val services = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false

            val splitter = android.text.TextUtils.SimpleStringSplitter(':')
            splitter.setString(services)
            while (splitter.hasNext()) {
                if (splitter.next().equals(component, ignoreCase = true)) return true
            }
            return false
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    private lateinit var windowManager: WindowManager
    private lateinit var inflater: LayoutInflater

    /** The rules, refreshed whenever the app pushes a new set. */
    @Volatile
    private var rules: ShieldRules = ShieldRules.EMPTY

    /**
     * Packages that must never be covered, whatever the rules say. Getting any
     * of these wrong locks the user out of their own device — the launcher and
     * the keyboard especially, since neither can be escaped from inside the
     * block screen.
     */
    private val exempt = linkedSetOf<String>()

    /** The package the current block screen is covering, if any. */
    private var blockedPackage: String? = null
    private var overlay: View? = null

    /** In-memory, so a kill or a restart clears it. That is the right lifetime
     *  for "you asked for five minutes of access". */
    private val graceUntil = HashMap<String, Long>()

    private var lastPackage: String? = null
    private var lastCheckAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        inflater = LayoutInflater.from(this)
        exempt += buildExemptSet()
        rules = ShieldStore.load(this)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        dismissOverlay()
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        dismissOverlay()
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onInterrupt() = Unit

    /** Re-reads the rules the app just wrote. Called from [ShieldBridge]. */
    fun refresh() {
        rules = ShieldStore.load(this)
    }

    /** Lets a package through for a while — the "open it anyway" path. */
    fun grantGrace(packageName: String, seconds: Int) {
        graceUntil[packageName] = SystemClock.uptimeMillis() + seconds * 1000L
        if (blockedPackage == packageName) dismissOverlay()
    }

    // -- The decision --------------------------------------------------------

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) {
            return
        }

        // Some OEM builds hand over a windows-changed event with no package on
        // it. There is nothing to decide without one, and guessing would mean
        // covering whatever happened to be in front.
        val packageName = event.packageName?.toString().orEmpty()
        if (packageName.isEmpty()) return

        if (packageName in exempt) {
            // Moving into a window we never cover means a screen that is up is
            // now stale.
            if (blockedPackage != null) dismissOverlay()
            return
        }

        // One launch produces a burst of window events. Re-deciding the same
        // package within a few frames is pure cost.
        val now = SystemClock.uptimeMillis()
        if (packageName == lastPackage && now - lastCheckAt < DEBOUNCE_MS) return
        lastPackage = packageName
        lastCheckAt = now

        if (blockedPackage != null && blockedPackage != packageName) dismissOverlay()
        if (blockedPackage == packageName) return

        val grace = graceUntil[packageName] ?: 0L
        if (now < grace) return

        val reason = reasonToBlock(packageName) ?: return
        showOverlay(packageName, reason)
    }

    /**
     * Why [packageName] should be covered right now, or null to let it run.
     *
     * Returns a human-readable reason rather than a boolean because the block
     * screen has to say something specific: "you set this to stay closed" and
     * "you are out of time" are different sentences, and a user who cannot tell
     * them apart cannot tell what to change.
     */
    private fun reasonToBlock(packageName: String): String? {
        val current = rules

        // The surface rules are additive, not decisive: they can only ever add
        // a reason. A user who closes Shorts and also blocks the app outright
        // must still be covered while watching an ordinary video, so a surface
        // rule that finds nothing falls through to the package rule instead of
        // clearing the app.
        if (packageName == YOUTUBE && current.youtube.any) {
            youtubeReason(current.youtube)?.let { return it }
        }

        val rule = current.ruleFor(packageName) ?: return null

        // Strict Mode is the one thing that overrides a budget: a daily
        // allowance the user can spend their way through is not a commitment,
        // so while a window is open every rule is a full block.
        if (current.strictModeActive(System.currentTimeMillis())) {
            return "Strict Mode is on. This stays closed until the window ends."
        }

        return when (rule.mode) {
            RuleMode.BLOCK -> "You asked FocusForge to keep this closed."
            RuleMode.BUDGET -> {
                val budget = rule.budgetMinutes
                if (budget <= 0) return null
                // Usage access not granted reads as zero, which would silently
                // disable every budget. The app surfaces the missing permission;
                // here it means "cannot tell, so do not act".
                if (!hasUsageAccess()) return null
                val used = usedTodayMillis(packageName)
                if (used >= budget * 60_000L) {
                    "You have used your $budget minutes for today."
                } else {
                    null
                }
            }
        }
    }

    /**
     * The YouTube surfaces.
     *
     * YouTube is one package holding both lectures and the Shorts feed, so a
     * package-level decision cannot express what the user asked for. The view
     * ids below are YouTube's own naming, and they are the only on-screen
     * content this service ever looks at — bounded, never stored, and only
     * while the YouTube rules are on.
     */
    private fun youtubeReason(youtube: YoutubeRules): String? {
        val root = rootInActiveWindow ?: return null

        var shorts = false
        var player = false
        var results = false

        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val node = queue.removeFirst()
            visited++
            val id = node.viewIdResourceName
            if (id != null) {
                if (id.contains("reel_") || id.contains("shorts")) shorts = true
                if (id.contains("player_view") || id.contains("watch_player")) {
                    player = true
                }
                if (id.contains("results")) results = true
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }

        return when {
            shorts && youtube.shorts -> "You asked FocusForge to keep Shorts closed."
            results && !player && youtube.feed ->
                "You asked FocusForge to keep the YouTube feed closed."
            else -> null
        }
    }

    // -- Usage ---------------------------------------------------------------

    private fun hasUsageAccess(): Boolean = try {
        val appOps = getSystemService(Context.APP_OPS_SERVICE)
            as android.app.AppOpsManager
        appOps.unsafeCheckOpNoThrow(
            android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            packageName,
        ) == android.app.AppOpsManager.MODE_ALLOWED
    } catch (_: Exception) {
        false
    }

    /** Foreground time since midnight, in milliseconds. */
    private fun usedTodayMillis(packageName: String): Long {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE)
            as? UsageStatsManager ?: return 0L

        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val stats = try {
            manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                midnight,
                System.currentTimeMillis(),
            )
        } catch (_: Exception) {
            null
        } ?: return 0L

        return stats.firstOrNull { it.packageName == packageName }
            ?.totalTimeInForeground ?: 0L
    }

    // -- The block screen ----------------------------------------------------

    private fun showOverlay(packageName: String, reason: String) {
        dismissOverlay()

        val view = inflater.inflate(R.layout.ff_block_overlay, null)
        val label = labelFor(packageName)

        view.findViewById<ImageView>(R.id.ff_block_icon)?.apply {
            setImageDrawable(iconFor(packageName))
        }
        view.findViewById<TextView>(R.id.ff_block_app)?.text = label
        view.findViewById<TextView>(R.id.ff_block_reason)?.text = reason
        view.findViewById<TextView>(R.id.ff_block_note)?.text =
            "Nothing has been deleted. You can change this any time in FocusForge."

        view.findViewById<Button>(R.id.ff_block_back)?.apply {
            text = "Take me back"
            setOnClickListener { leave(packageName, label) }
        }
        view.findViewById<Button>(R.id.ff_block_anyway)?.apply {
            text = "Open it anyway"
            setOnClickListener { openAnyway(packageName, label) }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        try {
            windowManager.addView(view, params)
            overlay = view
            blockedPackage = packageName
        } catch (_: Exception) {
            // A window we cannot add is a block we cannot draw. Getting the
            // user out of the app is the next best thing, and it is much better
            // than leaving them in it with no signal at all.
            overlay = null
            blockedPackage = null
            performGlobalAction(GLOBAL_ACTION_BACK)
            ShieldEvents.emit(packageName, label, ShieldEvents.WALKED_AWAY)
        }
    }

    private fun dismissOverlay() {
        val view = overlay ?: return
        overlay = null
        blockedPackage = null
        try {
            windowManager.removeView(view)
        } catch (_: Exception) {
            // Already detached — the service is going away, or the window was
            // pulled out from under us.
        }
    }

    /** The primary action: out of the app, back to whatever was underneath. */
    private fun leave(packageName: String, label: String) {
        dismissOverlay()
        ShieldEvents.emit(packageName, label, ShieldEvents.WALKED_AWAY)
        performGlobalAction(GLOBAL_ACTION_BACK)

        // Back does nothing on an app that is sitting on its own root screen,
        // which is exactly where a launcher icon drops you. If it did not take,
        // Home always will.
        handler.postDelayed({
            val front = rootInActiveWindow?.packageName?.toString()
            if (front == packageName) performGlobalAction(GLOBAL_ACTION_HOME)
        }, FALLBACK_HOME_DELAY_MS)
    }

    /**
     * The quiet action. FocusForge comes to the front and the app the user
     * tapped waits behind it.
     *
     * The grace is deliberately *not* granted here. The pause that follows
     * lasts longer than the grace does, so starting the clock now would spend
     * it before the user ever reached the app — and they would be covered
     * again the moment they opened it. The app grants the grace when the pause
     * is actually over.
     *
     * Nothing is reported here either. The impulse log carries one row per
     * interception, and for this exit the app is the side that knows the
     * outcome: it is the side that shows the pause, and a row written here as
     * well would count the same reach-for-it twice.
     */
    private fun openAnyway(packageName: String, label: String) {
        dismissOverlay()

        try {
            startActivity(
                Intent(this, Class.forName("dev.focusforge.focusforge.MainActivity"))
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP,
                    )
                    .putExtra(EXTRA_BLOCKED_PACKAGE, packageName)
                    .putExtra(EXTRA_BLOCKED_LABEL, label)
                    .putExtra(EXTRA_GRACE_SECONDS, rules.graceSeconds),
            )
        } catch (_: Exception) {
            // No UI to hand over to, so nothing will grant the grace later and
            // nothing will report the decision either. Both happen here: the
            // grant is the only way out that is not a loop of block screens,
            // and the report is the only record this interception will get.
            ShieldEvents.emit(packageName, label, ShieldEvents.OPENED_ANYWAY)
            grantGrace(packageName, rules.graceSeconds)
        }
    }

    // -- Lookups -------------------------------------------------------------

    private fun buildExemptSet(): Set<String> {
        val set = linkedSetOf(
            packageName,
            "com.android.systemui",
            "com.android.settings",
        )

        // The launcher. Without this, "Take me back" lands on a screen we then
        // cover, and there is no way out at all.
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        home.resolveActivity(packageManager)?.packageName?.let { set += it }

        // The keyboard. It shows as a window-state change of its own, and
        // covering it would make every text field on the device unusable.
        val ime = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD,
        )
        ime?.substringBefore('/')?.takeIf { it.isNotEmpty() }?.let { set += it }

        return set
    }

    private fun labelFor(packageName: String): String = try {
        packageManager.getApplicationLabel(
            packageManager.getApplicationInfo(packageName, 0),
        ).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        rules.ruleFor(packageName)?.label ?: packageName
    }

    private fun iconFor(packageName: String) = try {
        packageManager.getApplicationIcon(packageName)
    } catch (_: PackageManager.NameNotFoundException) {
        applicationInfo.loadIcon(packageManager)
    }
}
