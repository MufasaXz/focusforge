package dev.focusforge.focusforge

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import dev.focusforge.focusforge.widgets.FocusWidget
import dev.focusforge.focusforge.widgets.FocusLiveActivity
import android.content.res.Configuration
import io.flutter.plugin.common.MethodChannel
import dev.focusforge.focusforge.shield.AppBlockingService
import dev.focusforge.focusforge.shield.ShieldBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        super.onDestroy()
    }
}
