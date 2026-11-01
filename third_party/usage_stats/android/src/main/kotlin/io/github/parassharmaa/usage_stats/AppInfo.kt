package io.github.parassharmaa.usage_stats

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

object AppInfo {
    /**
     * Metadata for every installed package the caller is allowed to see.
     *
     * On API 30+ Android package-visibility rules apply: without a `<queries>`
     * entry or QUERY_ALL_PACKAGES this returns only visible packages. The plugin
     * deliberately does not request QUERY_ALL_PACKAGES (a Play-policy sensitive
     * permission); add it in your app if you need the full list.
     */
    fun queryInstalledApps(
        context: Context,
        includeSystem: Boolean,
    ): List<Map<String, String?>> {
        val pm = context.packageManager
        return pm
            .getInstalledPackages(0)
            .filter { packageInfo ->
                val appInfo = packageInfo.applicationInfo
                appInfo != null && (includeSystem || !appInfo.isSystemApp())
            }.map { appInfoMap(pm, it) }
    }

    /** PNG-encoded launcher icon for [packageName], or null if it cannot be resolved. */
    fun getAppIcon(
        context: Context,
        packageName: String,
    ): ByteArray? =
        try {
            drawableToPngBytes(context.packageManager.getApplicationIcon(packageName))
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }

    /**
     * Name, label and system flag — the three things the Shield list shows.
     * Versions and install times are not read: nothing in the app uses them.
     */
    private fun appInfoMap(
        pm: PackageManager,
        packageInfo: PackageInfo,
    ): Map<String, String?> {
        val appInfo = packageInfo.applicationInfo
        return mapOf(
            "packageName" to packageInfo.packageName,
            "appName" to appInfo?.let { pm.getApplicationLabel(it).toString() },
            "isSystemApp" to (appInfo?.isSystemApp() ?: false).toString(),
        )
    }

    private fun ApplicationInfo.isSystemApp(): Boolean = (flags and ApplicationInfo.FLAG_SYSTEM) != 0

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val bitmap =
            if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 1
                val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 1
                val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    }
}
