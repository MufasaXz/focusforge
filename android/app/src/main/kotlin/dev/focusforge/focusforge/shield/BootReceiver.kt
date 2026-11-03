package dev.focusforge.focusforge.shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores app boundaries the user already chose after a reboot or app update.
 *
 * Both broadcasts come only from the system, and neither enables anything: no
 * rules, a missing grant or the notification's Stop latch all leave it stopped.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                AppBlockingService.syncAfterRestart(context.applicationContext)
        }
    }
}
