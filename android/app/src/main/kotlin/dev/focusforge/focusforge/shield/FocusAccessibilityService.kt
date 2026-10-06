package dev.focusforge.focusforge.shield

import android.accessibilityservice.AccessibilityService
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Handler
import android.os.HandlerThread
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

        /** How long a passing window gets before the block screen comes down. */
        private const val DISMISS_CONFIRM_MS = 400L

        /** Bound on the YouTube window walk, so a deep tree cannot stall the
         *  launch path it is running on. */
        private const val MAX_NODES = 400

        private const val YOUTUBE = "com.google.android.youtube"

        /**
         * View ids that only exist while the Shorts player is on screen.
         *
         * Deliberately not "reel_" or "shorts": the home feed's Shorts carousel
         * carries those too, and matching them closed all of YouTube the moment
         * it launched.
         */
        private val SHORTS_PLAYER_IDS = listOf(
            "reel_recycler",
            "reel_pager",
            "reel_watch",
            "reel_player",
            "shorts_player",
        )

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

    /**
     * Where the YouTube window is read.
     *
     * Walking that tree is hundreds of synchronous calls into another process,
     * and `onAccessibilityEvent` runs on the main thread. Doing it there stalls
     * the service's own looper — and with it the system's accessibility
     * pipeline — for as long as the walk takes, which on a heavy feed is long
     * enough that the app being inspected stops drawing. YouTube in particular
     * came up as a black window.
     */
    private val worker = HandlerThread("ff-shield-inspect").apply { start() }
    private val inspector = Handler(worker.looper)

    /** One inspection at a time; a burst of window events must not queue up. */
    private var inspecting = false

    private lateinit var windowManager: WindowManager
    private lateinit var inflater: LayoutInflater

    /** The rules, refreshed whenever the app pushes a new set. */
    @Volatile
    private var rules: ShieldRules = ShieldRules.EMPTY

    /** The payload [rules] was parsed from, so a re-read is a string compare. */
    @Volatile
    private var rulesRaw: String? = null

    /**
     * The live rule set, re-read on every use.
     *
     * The service used to hold whatever it was handed at connect time and wait
     * to be told about changes. Anything that missed that one call — a config
     * written while the service was reconnecting, a rule added in the moment
     * before it was bound — left it enforcing yesterday's list, which is
     * indistinguishable from the shield having quietly switched itself off.
     * Reading the store every time removes the failure mode rather than
     * narrowing it: there is no cached copy left to go stale.
     */
    private fun currentRules(): ShieldRules {
        val raw = ShieldStore.raw(this)
        if (raw == rulesRaw) return rules
        val parsed = ShieldRules.parse(raw)
        rulesRaw = raw
        rules = parsed
        return parsed
    }

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
        rulesRaw = null
        currentRules()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        dismissOverlay()
        if (instance === this) instance = null
        // `true` asks the framework to call `onRebind` rather than dropping the
        // binding outright when it tears the service down for a config change
        // or a package update. Without it the shield goes dark until Android
        // decides to reconnect on its own.
        return true
    }

    override fun onRebind(intent: Intent?) {
        super.onRebind(intent)
        instance = this
        rulesRaw = null
        currentRules()
    }

    override fun onDestroy() {
        dismissOverlay()
        worker.quitSafely()
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onInterrupt() = Unit

    /** Re-reads the rules the app just wrote, and re-decides what is in front. */
    fun refresh() {
        rulesRaw = null
        currentRules()
        recheckForeground()
    }

    /**
     * Re-runs the decision for whatever is on screen right now.
     *
     * A rule the user has just added has to apply to the app they are looking
     * at, not only to the next launch. Without this the block only took effect
     * on some later window event, so an app that was already open — or already
     * sitting in the background when the rule was added — simply came forward
     * unrestricted.
     */
    fun recheckForeground() {
        val front = rootInActiveWindow?.packageName?.toString().orEmpty()
        if (front.isEmpty() || front in exempt) return
        lastPackage = null
        lastCheckAt = 0L
        decide(front)
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

        if (blockedPackage == packageName) return

        // Something other than the covered app is in front. That is *not* on
        // its own a reason to take the block screen down: system dialogs, the
        // keyboard, an ad or analytics process and Google Play services all
        // raise window events of their own while the blocked app is still the
        // one the user is looking at. Dropping the overlay for each of them and
        // putting it back a moment later is the flicker that reads as the app
        // glitching and restarting. So the dismissal is deferred and confirmed
        // against what is actually in front by then.
        if (blockedPackage != null) {
            confirmDismissal(packageName)
            return
        }

        decide(packageName)
    }

    /** Decides whether [packageName] should be covered, and covers it. */
    private fun decide(packageName: String) {
        val now = SystemClock.uptimeMillis()
        if (now < (graceUntil[packageName] ?: 0L)) return

        val current = currentRules()

        // The cheap path, and the common one: no YouTube rule in play means the
        // decision needs nothing but the package name.
        if (packageName != YOUTUBE || !current.youtube.any) {
            packageReason(packageName, current)?.let { showOverlay(packageName, it) }
            return
        }

        // YouTube needs its window read, and that happens off the main thread.
        // Capture the root here — one call — and walk it on the worker.
        val root = rootInActiveWindow
        if (inspecting) return
        inspecting = true
        inspector.post {
            val reason = youtubeReason(current.youtube, root)
                ?: packageReason(packageName, current)
            handler.post {
                inspecting = false
                if (reason != null) showOverlay(packageName, reason)
            }
        }
    }

    /**
     * Takes the block screen down only once the covered app is really gone.
     *
     * Re-checks a moment later instead of trusting the event that triggered it,
     * because most of the packages that raise a window event while an app is
     * covered are passing through rather than replacing it.
     */
    private fun confirmDismissal(candidate: String) {
        if (candidate in exempt) {
            dismissOverlay()
            return
        }
        handler.postDelayed({
            val front = rootInActiveWindow?.packageName?.toString().orEmpty()
            if (front == blockedPackage) return@postDelayed
            dismissOverlay()
            // Whatever the user moved to is a decision of its own. Without this
            // the first switch away from a covered app lands on an app that is
            // never asked about, and a blocked one opens unblocked.
            if (front.isNotEmpty() && front !in exempt) decide(front)
        }, DISMISS_CONFIRM_MS)
    }

    /**
     * Why [packageName] should be covered right now, or null to let it run.
     *
     * Returns a human-readable reason rather than a boolean because the block
     * screen has to say something specific: "you set this to stay closed" and
     * "you are out of time" are different sentences, and a user who cannot tell
     * them apart cannot tell what to change.
     */
    private fun packageReason(packageName: String, current: ShieldRules): String? {
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
     *
     * The distinction that matters is between the Shorts *player* and the
     * Shorts *shelf*. The home feed carries a Shorts carousel, and its ids
     * contain "shorts" and "reel_" just as the player's do. Matching those
     * alone meant that turning on "Block Shorts" closed YouTube the moment it
     * opened — the carousel on the home page was mistaken for someone watching
     * Shorts, and the app never got as far as loading. Only ids that exist
     * solely while the vertical player is on screen count.
     */
    private fun youtubeReason(
        youtube: YoutubeRules,
        root: AccessibilityNodeInfo?,
    ): String? {
        if (root == null) return null

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
                if (SHORTS_PLAYER_IDS.any { id.contains(it) }) shorts = true
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

        // A decision can be made a frame or two after the event that started
        // it, and by then the user may have moved on. Covering whatever is in
        // front now would be covering an app that was never asked about.
        val front = rootInActiveWindow?.packageName?.toString().orEmpty()
        if (front.isNotEmpty() && front != packageName) return

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
                    .putExtra(EXTRA_GRACE_SECONDS, currentRules().graceSeconds),
            )
        } catch (_: Exception) {
            // No UI to hand over to, so nothing will grant the grace later and
            // nothing will report the decision either. Both happen here: the
            // grant is the only way out that is not a loop of block screens,
            // and the report is the only record this interception will get.
            ShieldEvents.emit(packageName, label, ShieldEvents.OPENED_ANYWAY)
            grantGrace(packageName, currentRules().graceSeconds)
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
        currentRules().ruleFor(packageName)?.label ?: packageName
    }

    private fun iconFor(packageName: String) = try {
        packageManager.getApplicationIcon(packageName)
    } catch (_: PackageManager.NameNotFoundException) {
        applicationInfo.loadIcon(packageManager)
    }
}
