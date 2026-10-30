package dev.focusforge.focusforge.shield

import android.content.Context
import android.util.AttributeSet
import android.view.KeyEvent
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/** Handles Back before child focus dispatch while leaving system Home/Recents available. */
class BlockOverlayRoot @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    var onBack: (() -> Unit)? = null

    init {
        // The window is laid out in screen coordinates, so it spans the system
        // bars and the cutout. `fitsSystemWindows` on the layout was not enough:
        // it reads whatever insets the window was given, and an overlay raised
        // over a full-screen app inherits that app's hidden bars — zero insets,
        // then bars that come back once the cover is up. The bottom of the
        // screen ended up under the navigation bar, which is why the note and
        // the second button were cut off over some apps. Pad from the insets
        // each time they are delivered instead, and ask for them on attach so
        // the first frame is already correct.
        ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ViewCompat.requestApplyInsets(this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val leave = onBack
        if (leave != null && event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) leave()
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
