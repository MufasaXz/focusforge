package io.github.parassharmaa.usage_stats

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * UsageStatsPlugin, cut down to the five calls FocusForge makes.
 *
 * Upstream also exposes network, storage, configuration and standby queries,
 * and per-package metadata such as versions and install times. FocusForge uses
 * none of them, and a device-data call that ships unused is still a call the
 * app can make, so they are removed rather than left dormant.
 */
class UsageStatsPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    // Plugin-owned scope so background work is tied to the engine lifecycle
    // and cancelled on detach, instead of leaking through GlobalScope.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "usage_stats")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
        scope.cancel()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val context = this.context
        if (context == null) {
            result.error("no_context", "usage_stats is not attached to a context", null)
            return
        }
        when (call.method) {
            "isUsagePermission" -> result.success(Utils.isUsagePermission(context))

            "openUsageAccessSettings" -> {
                Utils.openUsageAccessSettings(context)
                result.success(null)
            }

            "queryEvents" -> runAsync(result) {
                UsageStats.queryEvents(context, call.longArg("start"), call.longArg("end"))
            }

            "queryInstalledApps" -> runAsync(result) {
                AppInfo.queryInstalledApps(
                    context,
                    call.argument<Boolean>("includeSystem") ?: true,
                )
            }

            "getAppIcon" -> runAsync(result) {
                AppInfo.getAppIcon(context, call.stringArg("packageName"))
            }

            else -> result.notImplemented()
        }
    }

    /** Run [block] on the IO dispatcher and deliver its value on the main thread. */
    private fun runAsync(
        result: Result,
        block: suspend () -> Any?,
    ) {
        scope.launch {
            try {
                val value = withContext(Dispatchers.IO) { block() }
                result.success(value)
            } catch (e: Exception) {
                result.error("usage_stats_error", e.message, null)
            }
        }
    }

    private fun MethodCall.longArg(key: String): Long =
        (argument<Number>(key) ?: error("Missing argument: $key")).toLong()

    private fun MethodCall.stringArg(key: String): String = argument<String>(key) ?: error("Missing argument: $key")
}
