package dev.focusforge.focusforge

import android.content.Intent
import dev.focusforge.focusforge.widgets.FocusWidget
import io.flutter.plugin.common.MethodChannel
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bridge = ShieldBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.attach() }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focusforge/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> { FocusWidget.refresh(applicationContext); result.success(null) }
                "takeFocusLaunch" -> {
                    val open = intent?.getBooleanExtra("open_focus", false) ?: false
                    intent?.removeExtra("open_focus")
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

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        super.onDestroy()
    }
}
