package dev.focusforge.focusforge.shield

import android.animation.Animator
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.content.Context
import android.provider.Settings
import android.util.AttributeSet
import android.view.KeyEvent
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import dev.focusforge.focusforge.R

/** Handles Back before child focus dispatch while leaving system Home/Recents available. */
class BlockOverlayRoot @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    var onBack: (() -> Unit)? = null

    private val breathing = mutableListOf<Animator>()

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
        startBreathing()
    }

    override fun onDetachedFromWindow() {
        stopBreathing()
        super.onDetachedFromWindow()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val leave = onBack
        if (leave != null && event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) leave()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    /**
     * The rings behind the blocked app's icon swell and settle like a slow
     * breath, the screen's only motion and a cue for the pause it offers.
     * The outer ring follows the inner one a beat later. With the system's
     * animation scale at zero the rings stay still.
     */
    private fun startBreathing() {
        stopBreathing()
        val scale = Settings.Global.getFloat(
            context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
        )
        if (scale == 0f) return
        val rings = listOf(
            Triple(R.id.ff_block_halo_inner, INNER_ALPHA, 0L),
            Triple(R.id.ff_block_halo_outer, OUTER_ALPHA, BREATH_MS / 3),
        )
        for ((id, alpha, delay) in rings) {
            val ring = findViewById<View>(id) ?: continue
            breathing += ObjectAnimator.ofPropertyValuesHolder(
                ring,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 0.9f, 1.06f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.9f, 1.06f),
                PropertyValuesHolder.ofFloat(View.ALPHA, alpha, alpha * 0.45f),
            ).apply {
                duration = BREATH_MS
                startDelay = delay
                repeatCount = ValueAnimator.INFINITE
                repeatMode = ValueAnimator.REVERSE
                interpolator = AccelerateDecelerateInterpolator()
                start()
            }
        }
    }

    private fun stopBreathing() {
        breathing.forEach { it.cancel() }
        breathing.clear()
        // A cancelled breath leaves the rings mid-swell; put them back so a
        // cover attached again starts from rest.
        for ((id, alpha) in listOf(
            R.id.ff_block_halo_inner to INNER_ALPHA,
            R.id.ff_block_halo_outer to OUTER_ALPHA,
        )) {
            findViewById<View>(id)?.apply {
                scaleX = 1f
                scaleY = 1f
                this.alpha = alpha
            }
        }
    }

    private companion object {
        const val BREATH_MS = 4000L

        // The resting strength of each ring, matching the layout's alpha.
        const val INNER_ALPHA = 0.18f
        const val OUTER_ALPHA = 0.10f
    }
}
