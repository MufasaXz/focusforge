package dev.focusforge.focusforge

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import dev.focusforge.focusforge.assistant.PipNudges
import dev.focusforge.focusforge.shield.AppBlockingService
import dev.focusforge.focusforge.shield.FocusAccessibilityService
import dev.focusforge.focusforge.shield.ShieldBridge
import dev.focusforge.focusforge.shield.ShieldEvents
import dev.focusforge.focusforge.widgets.FocusLiveActivity
import dev.focusforge.focusforge.widgets.FocusWidget
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's single activity.
 *
 * Beyond hosting Flutter it registers the shield bridge, and it forwards the
 * intent the accessibility service sends when the user chooses to open a
 * blocked app anyway — that intent is what turns a block screen into a
 * conversation about the rule rather than a dead end.
 */
class MainActivity : FlutterActivity() {
    private var bridge: ShieldBridge? = null
    private var export: DataExport? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Establish the native window policy before Flutter draws. Flutter's
        // SafeArea/MediaQuery insets keep controls clear of the system bars.
        //
        // Spelled out rather than delegated to WindowCompat.enableEdgeToEdge,
        // which calls Window.setStatusBarColor and setNavigationBarColor with
        // no version guard of its own. Both are deprecated and both are
        // no-ops from Android 15, and Play Console reports an unguarded call
        // against this app even when the call sits inside androidx — R8 moves
        // the method body into one of our own classes, so it is our package
        // name in the report. Everything below is a current API. The bar
        // colours those two setters used to supply on Android 14 and older
        // come from the window theme instead; see values/styles.xml.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Draw into the cutout rather than letting the system letterbox it
        // away. ALWAYS from Android 11, where it covers the waterfall edges
        // too; SHORT_EDGES before that, which is as far as Android 9 and 10
        // go.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        WindowManager.LayoutParams
                            .LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    } else {
                        WindowManager.LayoutParams
                            .LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                    }
            }
        }

        // Android 10 through 14 paint their own scrim behind a transparent
        // bar unless told not to. The app's own surface already sits there,
        // and a second translucent layer over it reads as a seam.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bridge = ShieldBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.attach() }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.focusforge/pip").setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    val items = call.argument<List<Map<String, Any?>>>("items")
                    val reminders = items.orEmpty().mapNotNull { item ->
                        val id = (item["id"] as? Number)?.toInt()
                        val at = (item["at"] as? Number)?.toLong()
                        val title = item["title"] as? String
                        val body = item["body"] as? String
                        val stale = (item["stale"] as? Number)?.toLong() ?: 3 * 60 * 60 * 1000L
                        if (id == null || at == null || title.isNullOrBlank() || body.isNullOrBlank()) {
                            null
                        } else {
                            PipNudges.Reminder(id, at, title, body, stale)
                        }
                    }
                    PipNudges.schedule(applicationContext, reminders)
                    result.success(null)
                }
                "clear" -> {
                    PipNudges.clear(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val saver = DataExport(this).also { export = it }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.focusforge/privacy").setMethodCallHandler { call, result ->
            val stores = listOf("focusforge_shield", "pip_nudges", "focusforge_live_activity")
            when (call.method) {
                "export" -> result.success(stores.associateWith { name ->
                    getSharedPreferences(name, MODE_PRIVATE).all
                })
                "erase" -> {
                    PipNudges.clear(applicationContext)
                    stopService(Intent(this, AppBlockingService::class.java))
                    ShieldEvents.clear()
                    Thread {
                        val outcome = runCatching {
                            for (name in stores) check(getSharedPreferences(name, MODE_PRIVATE).edit().clear().commit())
                            for (file in cacheDir.listFiles().orEmpty()) check(file.deleteRecursively())
                        }
                        runOnUiThread {
                            if (outcome.isSuccess) result.success(null)
                            else result.error("cleanup-failed", "Local cleanup could not finish. Please retry.", null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DataExport.CHANNEL).setMethodCallHandler { call, result ->
            val name = call.argument<String>("name")
            val json = call.argument<String>("json")
            if (call.method == "save" && name != null && json != null) {
                saver.save(name, json, result)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focusforge/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    FocusWidget.refresh(applicationContext)
                    FocusLiveActivity.refresh(applicationContext)
                    result.success(null)
                }
                "takeFocusLaunch" -> {
                    val open = intent?.getBooleanExtra("open_focus", false) ?: false
                    intent?.removeExtra("open_focus")
                    result.success(open)
                }
                "takeDashboardLaunch" -> {
                    val open = intent?.getBooleanExtra("open_dashboard", false) ?: false
                    intent?.removeExtra("open_dashboard")
                    result.success(open)
                }
                "takeStrictLaunch" -> {
                    val open = intent?.getBooleanExtra(AppBlockingService.EXTRA_OPEN_STRICT_MODE, false) ?: false
                    intent?.removeExtra(AppBlockingService.EXTRA_OPEN_STRICT_MODE)
                    result.success(open)
                }
                else -> result.notImplemented()
            }
        }

        // The intent that started us may already carry a blocked package, so
        // record it before the first frame asks for it.
        ShieldBridge.recordLaunch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // `singleTop` means a second interception reuses this instance, so the
        // new intent has to be adopted rather than ignored.
        setIntent(intent)
        ShieldBridge.recordLaunch(intent)
    }

    override fun onResume() {
        super.onResume()
        FocusAccessibilityService.instance?.dismissForOwnApp()
        AppBlockingService.activityVisible = true
        AppBlockingService.sync(applicationContext)
        // Includes returning from notification permission/settings changes.
        FocusWidget.refresh(applicationContext)
        FocusLiveActivity.refresh(applicationContext)
    }

    override fun onPause() {
        AppBlockingService.activityVisible = false
        super.onPause()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        FocusWidget.refresh(applicationContext)
    }

    @Deprecated("Flutter's embedding still delivers picker results here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (export?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        export?.dispose()
        export = null
        super.onDestroy()
    }
}
