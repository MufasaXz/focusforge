package dev.focusforge.focusforge.shield

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Dart side of the shield.
 *
 * Deliberately thin. Everything that has to keep working when the Flutter
 * engine is not running lives in [FocusAccessibilityService]; this class only
 * carries config down and events up. A method that needed the service to be
 * alive would be a method that stops working the moment the user swipes the app
 * away — which is precisely when blocking matters most.
 */
class ShieldBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "dev.focusforge/shield"
        const val EVENT_CHANNEL = "dev.focusforge/shield_events"

        /**
         * Set by [MainActivity] when the service launched it from a block
         * screen, so the app can open on the rule the user just hit. Static
         * because the intent arrives before any engine exists to hand it to.
         */
        @Volatile
        private var launchExtras: Map<String, Any>? = null

        fun recordLaunch(intent: Intent?) {
            val packageName = intent
                ?.getStringExtra(FocusAccessibilityService.EXTRA_BLOCKED_PACKAGE)
            // An ordinary launch clears the pending one rather than leaving it
            // to be delivered later: these extras describe the intent that
            // started *this* launch, and replaying an older one would open the
            // app on a block the user has long since dealt with.
            launchExtras = if (packageName == null) {
                null
            } else {
                mapOf(
                    "package" to packageName,
                    "label" to (
                        intent.getStringExtra(FocusAccessibilityService.EXTRA_BLOCKED_LABEL)
                            ?: packageName
                        ),
                    "graceSeconds" to intent.getIntExtra(
                        FocusAccessibilityService.EXTRA_GRACE_SECONDS,
                        ShieldRules.DEFAULT_GRACE_SECONDS,
                    ),
                )
            }
        }

        /** Reads and clears the pending launch, so it is delivered once. */
        private fun takeLaunch(): Map<String, Any>? {
            val extras = launchExtras
            launchExtras = null
            return extras
        }
    }

    private val channel = MethodChannel(messenger, METHOD_CHANNEL)
    private val events = EventChannel(messenger, EVENT_CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    fun attach() {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isServiceEnabled" -> result.success(
                FocusAccessibilityService.isEnabled(context),
            )

            "openAccessibilitySettings" -> {
                // Android has no runtime dialog for accessibility access — the
                // only way in is this settings page, so the app sends the user
                // there rather than pretending to ask.
                try {
                    context.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }

            "applyConfig" -> {
                val raw = call.argument<String>("config")
                val rules = ShieldRules.parse(raw)
                // Disk first, then the live service. If the process dies between
                // the two, the next service start reads the new rules anyway.
                ShieldStore.save(context, rules)
                FocusAccessibilityService.instance?.refresh()
                result.success(true)
            }

            "grantTemporaryAccess" -> {
                val packageName = call.argument<String>("package")
                val seconds = call.argument<Int>("seconds")
                    ?: ShieldRules.DEFAULT_GRACE_SECONDS
                if (packageName.isNullOrBlank()) {
                    result.success(false)
                } else {
                    FocusAccessibilityService.instance
                        ?.grantGrace(packageName, seconds)
                    result.success(true)
                }
            }

            "openApp" -> {
                // The other half of "open it anyway": once the pause is over,
                // the app the user asked for is the app they get. Reached
                // through the launcher intent rather than a raw package name,
                // so an app with no launcher activity is a no rather than a
                // crash.
                val target = call.argument<String>("package")
                val launch = if (target.isNullOrBlank()) {
                    null
                } else {
                    context.packageManager.getLaunchIntentForPackage(target)
                }
                if (launch == null) {
                    result.success(false)
                } else {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    result.success(
                        try {
                            context.startActivity(launch)
                            true
                        } catch (_: Exception) {
                            false
                        },
                    )
                }
            }

            "protectedPackages" -> result.success(
                FocusAccessibilityService.protectedPackages(context).toList(),
            )

            "blockedApp" -> result.success(takeLaunch())

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        // `attach` drains anything the service reported while no engine was
        // listening, then switches to live delivery.
        ShieldEvents.attach { event ->
            main.post { sink.success(event) }
        }
    }

    override fun onCancel(arguments: Any?) {
        ShieldEvents.detach()
    }
}
