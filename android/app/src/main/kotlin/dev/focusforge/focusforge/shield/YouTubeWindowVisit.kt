package dev.focusforge.focusforge.shield

/** Window-event debounce and one loading retry belong to a single YouTube visit. */
class YouTubeWindowVisit(private val debounceMillis: Long) {
    private var lastPackage: String? = null
    private var lastCheckAt = 0L
    private var retryPackage: String? = null

    fun shouldInspect(packageName: String, now: Long): Boolean {
        if (packageName == lastPackage && now - lastCheckAt < debounceMillis) return false
        lastPackage = packageName
        lastCheckAt = now
        if (packageName != retryPackage) retryPackage = null
        return true
    }

    fun claimLoadingRetry(packageName: String): Boolean {
        val available = retryPackage != packageName
        retryPackage = packageName
        return available
    }

    fun end() {
        lastPackage = null
        lastCheckAt = 0L
        retryPackage = null
    }
}
