package dev.focusforge.focusforge

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Saves the "Export all data" JSON to a file the user picks with the system
 * file picker, so no storage permission is needed and the app never chooses
 * where personal data lands.
 *
 * One save at a time: the picker is modal, and a second request while it is
 * open is refused rather than queued behind it.
 */
class DataExport(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var text: String? = null
    private val writer = Executors.newSingleThreadExecutor()

    fun save(name: String, json: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A save is already open", null)
            return
        }
        val pick = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("application/json")
            .putExtra(Intent.EXTRA_TITLE, name)
        try {
            activity.startActivityForResult(pick, REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            result.success("unsupported")
            return
        }
        pending = result
        text = json
    }

    /** Returns whether [requestCode] was this class's to handle. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        val json = text
        pending = null
        text = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || json == null) {
            result.success("cancelled")
            return true
        }
        val resolver = activity.applicationContext.contentResolver
        // Off the main thread: an export can be large, and the target can be
        // a cloud provider that writes slowly.
        writer.execute {
            val outcome = try {
                resolver.openOutputStream(uri, "wt")?.use { stream ->
                    stream.write(json.toByteArray(Charsets.UTF_8))
                }
                    ?: throw IllegalStateException("No stream for $uri")
                "saved"
            } catch (e: Exception) {
                null
            }
            activity.runOnUiThread {
                if (outcome == null) {
                    result.error("write_failed", "Could not write the file", null)
                } else {
                    result.success(outcome)
                }
            }
        }
        return true
    }

    fun dispose() {
        pending?.success("cancelled")
        pending = null
        text = null
        writer.shutdown()
    }

    companion object {
        const val CHANNEL = "dev.focusforge/export"
        private const val REQUEST_CODE = 0x4645
    }
}
