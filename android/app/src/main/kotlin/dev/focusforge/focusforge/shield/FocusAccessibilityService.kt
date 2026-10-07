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

        /**
         * How often a live block screen re-checks itself.
         *
         * Nothing in the framework promises an overlay stays up: the system can
         * take one away when a window it belongs to changes, and a service that
         * only re-decides on window events would never notice. Half a second is
         * short enough that a dropped block is invisible and long enough that
         * the check costs nothing.
         */
        private const val WATCHDOG_MS = 500L

        /** Bound on the YouTube window walk, so a deep tree cannot stall the
         *  launch path it is running on. */
        private const val MAX_NODES = 400

        /**
         * How long YouTube gets to finish inflating before its window is read
         * a second time.
         *
         * The first event for a launch arrives while the feed is still being
         * built, so a rule that reads the tree once lets a feed that had not
         * loaded yet through. Long enough for the browse surface to appear,
         * short enough that the app is not usable in between.
         */
        private const val YOUTUBE_RECHECK_MS = 900L

        private const val YOUTUBE = "com.google.android.youtube"

        /** The status bar, the shade and the volume panel. */
        private const val SYSTEM_UI = "com.android.systemui"

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

        /**
         * View ids that only exist on a browse surface — the home feed and the
         * search results list.
         *
         * The home page does not advertise itself with a single id, and the
         * list has changed names across YouTube releases, so several are
         * matched and any one of them is enough. None of them appears on the
         * watch page, which is what keeps a lecture opened from a direct link
         * playing.
         */
        private val FEED_IDS = listOf(
            "results",
            "feed_recycler_view",
            "home_feed",
            "rich_grid",
        )

        /**
         * View ids that mean a video is actually being watched.
         *
         * Deliberately not `player_view`: the home page inflates a player
         * container for the miniplayer, so matching it read the feed as "a
         * video is playing" and the home block never fired — which is the bug
         * this list exists to close. The watch page's own player and its
         * controls are not present anywhere else.
         */
        private val WATCH_IDS = listOf(
            "watch_player",
            "player_controller",
            "fullscreen_player",
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
         * The packages the shield will never cover, whatever the rules say.
         *
         * Exposed so the app can say so on the row instead of offering a switch
         * that silently does nothing. Built from the same three lookups the
         * running service uses — this is deliberately the *only* definition, so
         * the list the user sees and the list the engine enforces cannot drift
         * apart.
         */
        fun protectedPackages(context: Context): Set<String> = setOfNotNull(
            context.packageName,
            SYSTEM_UI,
            "com.android.settings",
            homePackageOf(context),
            inputMethodPackageOf(context),
        )

        /** Where Home goes — the launcher, or whatever the user replaced it with. */
        fun homePackageOf(context: Context): String? = try {
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .resolveActivity(context.packageManager)
                ?.packageName
        } catch (_: Exception) {
            null
        }

        /** The keyboard. Covering it would make every text field unusable. */
        fun inputMethodPackageOf(context: Context): String? = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD,
            )?.substringBefore('/')?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }

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

    /**
     * The package the one delayed YouTube re-read has been spent on.
     *
     * The re-read is for a window that was still inflating, not a poll, so it
     * happens once per arrival: cleared when something else comes to the
     * front, which is what gives the next visit its own second look.
     */
    private var youtubeRetryFor: String? = null

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

    /**
     * Where Home goes. The one exempt package that means "the user left":
     * everything else in the set can raise a window event while the covered app
     * is still the one being looked at.
     */
    private var homePackage: String? = null

    /** The keyboard, which is never a destination either. */
    private var imePackage: String? = null

    /** The package the current block screen is covering, if any. */
    private var blockedPackage: String? = null

    /** Why it is covered, so the watchdog can put the screen back unchanged. */
    private var blockedReason: String? = null
    private var overlay: View? = null

    /**
     * Keeps a live block screen up.
     *
     * Started when the screen goes up and cancelled when it comes down, so it
     * costs nothing while the user is not being blocked. It exists because a
     * block that has quietly stopped working is worse than no block at all: the
     * user believes the app is closed and it is not.
     */
    private val watchdog = object : Runnable {
        override fun run() {
            val covered = blockedPackage ?: return
            val front = foregroundPackage()

            if (front != null && front != covered && front !in transient()) {
                // The user really did move on.
                dismissOverlay()
                decide(front)
                return
            }

            val view = overlay
            if (view == null || !view.isAttachedToWindow) {
                // Taken away under us. Put it back with the reason it had.
                val reason = blockedReason ?: return
                showOverlay(covered, reason)
                return
            }

            handler.postDelayed(this, WATCHDOG_MS)
        }
    }

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
        val front = foregroundPackage() ?: return
        if (front in exempt) return
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
        //
        // Named `foreground` rather than `packageName` on purpose: the service
        // has a `packageName` of its own, and shadowing it is how "is this the
        // block screen?" turns into a comparison against the wrong thing.
        val foreground = event.packageName?.toString().orEmpty()
        if (foreground.isEmpty()) return

        // The block screen is one of our own windows, and adding or removing it
        // raises window events of its own. Reading those as "the user moved on"
        // is how the shield used to dismiss itself a moment after appearing, so
        // our own package is not news: there is nothing to decide about it.
        if (foreground == packageName) return

        if (foreground in exempt) {
            if (blockedPackage != null) {
                // Home is the one exempt package that means the user left; the
                // rest — the keyboard, the status bar — can raise an event while
                // the covered app is still the one in front, so they get the
                // deferred check rather than an immediate teardown.
                if (foreground == homePackage) {
                    dismissOverlay()
                } else {
                    confirmDismissal()
                }
            }
            return
        }

        // One launch produces a burst of window events. Re-deciding the same
        // package within a few frames is pure cost.
        val now = SystemClock.uptimeMillis()
        if (foreground == lastPackage && now - lastCheckAt < DEBOUNCE_MS) return
        lastPackage = foreground
        lastCheckAt = now

        // A different arrival gets its own delayed second look: the one just
        // spent belonged to whatever came to the front before this.
        if (foreground != youtubeRetryFor) youtubeRetryFor = null

        if (blockedPackage == foreground) return

        // Something other than the covered app is in front. That is *not* on
        // its own a reason to take the block screen down: system dialogs, the
        // keyboard, an ad or analytics process and Google Play services all
        // raise window events of their own while the blocked app is still the
        // one the user is looking at. Dropping the overlay for each of them and
        // putting it back a moment later is the flicker that reads as the app
        // glitching and restarting. So the dismissal is deferred and confirmed
        // against what is actually in front by then.
        if (blockedPackage != null) {
            confirmDismissal()
            return
        }

        decide(foreground)
    }

    /** Decides whether [packageName] should be covered, and covers it. */
    private fun decide(packageName: String) {
        // Already covered by this exact screen. Re-showing it would take it
        // down and put it back for no reason, which is a visible flash.
        if (blockedPackage == packageName) return

        val now = SystemClock.uptimeMillis()
        if (now < (graceUntil[packageName] ?: 0L)) return

        val current = currentRules()

        // The cheap path, and the common one: no YouTube rule in play means the
        // decision needs nothing but the package name.
        if (packageName != YOUTUBE || !youtubeArmed(current)) {
            packageReason(packageName, current)?.let { showOverlay(packageName, it) }
            return
        }

        // YouTube needs its window read, and that happens off the main thread.
        // Capture the root here — one call — and walk it on the worker.
        if (inspecting) return
        inspecting = true
        val root = rootInActiveWindow
        // The first event for a launch arrives while the feed is still being
        // built, so a decision that finds nothing gets one delayed second look
        // — but only one, or a rule that does not match would poll forever.
        val retry = youtubeRetryFor != packageName
        youtubeRetryFor = packageName
        inspector.post {
            // The flag is cleared in a `finally`: a walk that throws (a window
            // that went away mid-read, a node recycled under it) used to leave
            // it set for the life of the service, and with it set every later
            // YouTube decision returned early — which is how the rules
            // appeared to switch themselves off until a restart.
            val reason = try {
                youtubeReason(current, root) ?: packageReason(packageName, current)
            } finally {
                handler.post { inspecting = false }
            }
            handler.post {
                when {
                    reason != null -> showOverlay(packageName, reason)
                    retry -> handler.postDelayed({
                        if (blockedPackage == null && foregroundPackage() == packageName) {
                            decide(packageName)
                        }
                    }, YOUTUBE_RECHECK_MS)
                }
            }
        }
    }

    /**
     * Takes the block screen down only once the covered app is really gone.
     *
     * Re-checks a moment later instead of trusting the event that triggered it,
     * because most of the packages that raise a window event while an app is
     * covered are passing through rather than replacing it — and because the
     * window that is active while the block screen is up may well be the block
     * screen itself.
     */
    private fun confirmDismissal() {
        handler.postDelayed({
            val covered = blockedPackage ?: return@postDelayed
            val front = foregroundPackage()

            // No evidence either way, or evidence that the covered app is still
            // there: leave the block alone.
            if (front == null || front == covered || front in transient()) {
                return@postDelayed
            }

            dismissOverlay()
            // Whatever the user moved to is a decision of its own. Without this
            // the first switch away from a covered app lands on an app that is
            // never asked about, and a blocked one opens unblocked.
            decide(front)
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
            RuleMode.FOCUS -> if (current.focusActive(System.currentTimeMillis())) {
                "This stays closed while you are focusing."
            } else {
                null
            }
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
     *
     * The feed rule has the mirror-image problem. It was reading the home page
     * as "a video is playing", because the home page inflates a player
     * container for the miniplayer, so the feed switch did nothing on the one
     * screen it was named after. It now asks whether a *watch* surface is up
     * ([WATCH_IDS]) rather than whether any player node exists, and matches
     * the browse surfaces by their own ids ([FEED_IDS]).
     */
    /**
     * Whether the YouTube surface switches apply right now.
     *
     * The two switches can be armed for the whole day or only for a focus
     * block; either way there is nothing to read on screen until one of them
     * is on, which is what keeps the window walk off the common path.
     */
    private fun youtubeArmed(current: ShieldRules): Boolean =
        current.youtube.any &&
            (
                !current.youtube.focusOnly ||
                    current.focusActive(System.currentTimeMillis())
                )

    private fun youtubeReason(
        current: ShieldRules,
        root: AccessibilityNodeInfo?,
    ): String? {
        if (root == null) return null
        if (!youtubeArmed(current)) return null

        val youtube = current.youtube
        var shorts = false
        var watching = false
        var feed = false

        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val node = queue.removeFirst()
            visited++
            val id = node.viewIdResourceName
            if (id != null) {
                if (SHORTS_PLAYER_IDS.any { id.contains(it) }) shorts = true
                if (WATCH_IDS.any { id.contains(it) }) watching = true
                if (FEED_IDS.any { id.contains(it) }) feed = true
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }

        return when {
            // Shorts first: the vertical player can sit over the feed, and
            // there the more specific reason is the one worth showing.
            shorts && youtube.shorts -> "You asked FocusForge to keep Shorts closed."
            feed && !watching && youtube.feed ->
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
        val front = foregroundPackage()
        if (front != null && front != packageName) return

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
            // Not focusable on purpose. A focusable overlay takes window focus
            // from the app underneath, and an app that loses focus can pause
            // its video, drop its state or redraw — which is part of what reads
            // as the blocked app glitching. Touch is unaffected: a
            // non-focusable window still receives every tap inside it, which is
            // how floating widgets have always worked.
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        try {
            windowManager.addView(view, params)
            overlay = view
            blockedPackage = packageName
            blockedReason = reason
            handler.removeCallbacks(watchdog)
            handler.postDelayed(watchdog, WATCHDOG_MS)
        } catch (_: Exception) {
            // A window we cannot add is a block we cannot draw. Getting the
            // user out of the app is the next best thing, and it is much better
            // than leaving them in it with no signal at all.
            overlay = null
            blockedPackage = null
            blockedReason = null
            performGlobalAction(GLOBAL_ACTION_BACK)
            ShieldEvents.emit(packageName, label, ShieldEvents.WALKED_AWAY)
        }
    }

    private fun dismissOverlay() {
        handler.removeCallbacks(watchdog)
        val view = overlay ?: return
        overlay = null
        blockedPackage = null
        blockedReason = null
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
            if (foregroundPackage() == packageName) {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
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
        homePackage = homePackageOf(this)
        imePackage = inputMethodPackageOf(this)
        return protectedPackages(this)
    }

    /**
     * The packages that can hold the active window while the covered app is
     * still the one in front.
     *
     * A keyboard rising, the status bar redrawing, our own block screen being
     * added — all of these raise window events without the user having gone
     * anywhere. None of them is a destination, so none of them ends a block.
     */
    private fun transient(): Set<String> =
        setOfNotNull(packageName, imePackage, SYSTEM_UI)

    /**
     * The package the user is actually looking at.
     *
     * `rootInActiveWindow` is not that on its own, and reading it as if it were
     * is what made the shield take itself down: the block screen is a window of
     * *this* app, so while it is up the active window can be ours. The service
     * concluded the covered app had been left, removed its own screen, and let
     * the app through — the restriction appeared for a second and then the app
     * worked.
     *
     * So our own package is never an answer. If the block screen is up, the app
     * underneath is still the one in front; if the app's own UI is up — the
     * pause screen, the settings — there is nothing to decide.
     *
     * Returns null when the foreground cannot be established, which callers
     * treat as "no evidence" rather than "gone".
     */
    private fun foregroundPackage(): String? {
        val front = rootInActiveWindow?.packageName?.toString().orEmpty()
        if (front.isEmpty()) return null
        if (front != packageName) return front
        return if (overlay != null) blockedPackage else null
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
