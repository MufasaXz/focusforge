package dev.focusforge.focusforge.shield

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.os.PowerManager
import android.view.accessibility.AccessibilityWindowInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.telecom.TelecomManager
import android.net.Uri
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
import dev.focusforge.focusforge.localization.DeviceStrings

/** Optional YouTube surface filters. Normal app boundaries use UsageEvents + draw-over-apps. */
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

        // Exact visible surface identities live in YouTubeSurfaceSignals.

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
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            homePackageOf(context),
            inputMethodPackageOf(context),
            defaultDialerOf(context),
            "com.android.phone",
            "com.android.server.telecom",
        ) + emergencyPackagesOf(context) + allHomePackagesOf(context)

        private fun allHomePackagesOf(context: Context): Set<String> = try {
            @Suppress("DEPRECATION")
            context.packageManager.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY,
            ).mapNotNull { it.activityInfo?.packageName }.toSet()
        } catch (_: Exception) { emptySet() }

        private fun defaultDialerOf(context: Context): String? = try {
            (context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage
        } catch (_: Exception) { null }

        private fun emergencyPackagesOf(context: Context): Set<String> = try {
            val pm = context.packageManager
            listOf(Intent(Intent.ACTION_DIAL, Uri.parse("tel:")),
                Intent("android.intent.action.EMERGENCY_ASSISTANCE"),
                Intent("com.android.phone.EmergencyDialer.DIAL")).flatMap { intent ->
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    .mapNotNull { it.activityInfo?.packageName }
            }.toSet()
        } catch (_: Exception) { emptySet() }


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
     * front or the block is dismissed, which gives the next visit its own second look.
     */
    private val windowVisit = YouTubeWindowVisit(DEBOUNCE_MS)

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
            val power = getSystemService(POWER_SERVICE) as PowerManager
            val lock = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            if (!youtubeArmed(currentRules()) || !power.isInteractive || lock.isKeyguardLocked) {
                dismissOverlay(); return
            }
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
        val current = currentRules()
        if (!youtubeArmed(current)) dismissOverlay()
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
        windowVisit.end()
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
        if (!YouTubeEventPolicy.accepts(type, event.contentChangeTypes)) {
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

        // Returning to the same package is still news when its block window
        // was detached during Recents. Recover before the ordinary debounce.
        if (blockedPackage == foreground && overlay?.isAttachedToWindow != true &&
            youtubeArmed(currentRules())) {
            blockedReason?.let { showOverlay(foreground, it) }
            return
        }

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
        if (!windowVisit.shouldInspect(foreground, now)) return

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

        // This service never enforces whole-app rules or reads another app's content.
        if (packageName != YOUTUBE || !youtubeArmed(current)) return
        if (AppBlockingService.instance?.isCovering(packageName) == true) return

        // YouTube needs its window read, and that happens off the main thread.
        // Capture the root here — one call — and walk it on the worker.
        if (inspecting) return
        inspecting = true
        val root = rootInActiveWindow
        // The first event for a launch arrives while the feed is still being
        // built, so a decision that finds nothing gets one delayed second look
        // — but only one, or a rule that does not match would poll forever.
        val retry = windowVisit.claimLoadingRetry(packageName)
        inspector.post {
            // The flag is cleared in a `finally`: a walk that throws (a window
            // that went away mid-read, a node recycled under it) used to leave
            // it set for the life of the service, and with it set every later
            // YouTube decision returned early — which is how the rules
            // appeared to switch themselves off until a restart.
            val signals = try {
                youtubeSignals(current, root)
            } finally {
                handler.post { inspecting = false }
            }
            handler.post {
                val live = currentRules()
                if (!youtubeArmed(live)) return@post
                val reason = signals?.reason(
                    live,
                    System.currentTimeMillis(),
                    SystemClock.uptimeMillis(),
                    graceUntil[packageName] ?: 0L,
                )
                when {
                    reason != null && foregroundPackage() == packageName -> {
                        showOverlay(packageName, reason)
                    }
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

    private fun youtubeSignals(
        current: ShieldRules,
        root: AccessibilityNodeInfo?,
    ): YouTubeSurfaceSignals? {
        if (root == null) return null
        if (!youtubeArmed(current)) return null
        // Window events and the active window can change between capture and
        // inspection. Never walk another app's content after a YouTube event.
        if (root.packageName?.toString() != YOUTUBE) return null

        val signals = YouTubeSurfaceSignals()

        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val node = queue.removeFirst()
            visited++
            val resourceId = node.viewIdResourceName
            val visible = node.isVisibleToUser
            signals.observe(resourceId, visible)
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }

        return signals
    }

    // -- The block screen ----------------------------------------------------

    fun dismissForAppBoundary(packageName: String) {
        if (blockedPackage == packageName) dismissOverlay()
    }

    private fun showOverlay(packageName: String, reason: String) {
        if (AppBlockingService.instance?.isCovering(packageName) == true) return
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
        view.findViewById<TextView>(R.id.ff_block_reason)?.text = DeviceStrings.reason(this, reason)
        view.findViewById<TextView>(R.id.ff_block_note)?.text =
            DeviceStrings.text(this, "Need access? Pause and breathe first.")

        view.findViewById<Button>(R.id.ff_block_back)?.apply {
            setOnClickListener { leave(packageName, label) }
        }
        view.findViewById<Button>(R.id.ff_block_anyway)?.apply {
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
            // The blocking surface is opaque immediately; only the content enters.
            // Respect Android's Remove animations setting and cancel on dismissal.
            val content = view.findViewById<View>(R.id.ff_block_content)
            applyOverlayTypeface(content)
            val motion = Settings.Global.getFloat(
                content.context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
            ) > 0f
            if (motion) {
                content.alpha = 0f
                content.translationY = 16f * resources.displayMetrics.density
                content.animate().alpha(1f).translationY(0f).setDuration(300L)
                    .setInterpolator(DecelerateInterpolator()).start()
            }
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

    private fun applyOverlayTypeface(view: View) {
        val regular = try {
            Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/Inter-Regular.ttf")
        } catch (_: Exception) { Typeface.create("sans-serif", Typeface.NORMAL) }
        val bold = try {
            Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/InterDisplay-SemiBold.ttf")
        } catch (_: Exception) { Typeface.create("sans-serif", Typeface.BOLD) }
        fun apply(child: View) {
            if (child is TextView) child.typeface = if (child.typeface?.isBold == true) bold else regular
            if (child is ViewGroup) for (i in 0 until child.childCount) apply(child.getChildAt(i))
        }
        apply(view)
    }

    private fun dismissOverlay() {
        handler.removeCallbacks(watchdog)
        val view = overlay
        overlay = null
        blockedPackage = null
        blockedReason = null
        // Package-filtered events do not report the launcher. Clear the old
        // visit here so a Recents return can inspect a loading surface again.
        windowVisit.end()
        if (view == null) return
        view.findViewById<View>(R.id.ff_block_content)?.animate()?.cancel()
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
        if (overlay != null) {
            // The accessibility overlay can become rootInActiveWindow itself.
            // Read package names only from application windows underneath it;
            // never inspect other apps' view IDs, text or contents.
            val apps = windows.filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                .mapNotNull { window ->
                    val root = window.root ?: return@mapNotNull null
                    val pkg = try { root.packageName?.toString() } finally {
                        @Suppress("DEPRECATION")
                        root.recycle()
                    }
                    if (pkg.isNullOrBlank()) null else ApplicationWindow(pkg, window.isActive, window.isFocused)
                }
            return foregroundApplication(apps)
        }
        val root = rootInActiveWindow ?: return null
        val front = try { root.packageName?.toString() } finally {
            @Suppress("DEPRECATION")
            root.recycle()
        }
        return front?.takeIf { it.isNotBlank() && it != packageName }
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
