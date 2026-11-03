package dev.focusforge.focusforge.shield

/** Visible, exact resource identities keep home shelves distinct from playback. */
class YouTubeSurfaceSignals {
    private var shorts = false
    private var watching = false
    private var feed = false
    fun observe(resourceId: String?, visible: Boolean) {
        if (!visible || resourceId == null ||
            !resourceId.startsWith("com.google.android.youtube:id/")) return
        when (resourceId.substringAfter(":id/")) {
            "reel_recycler", "reel_pager", "reel_watch", "reel_player",
            "reel_progress_bar", "shorts_player" -> shorts = true
            "watch_player", "player_controller", "fullscreen_player" -> watching = true
            "results", "feed_recycler_view", "home_feed", "rich_grid" -> feed = true
        }
    }
    fun reason(blockShorts: Boolean, blockFeed: Boolean): String? = when {
        shorts && blockShorts -> "Shorts are paused. Keep your focus."
        feed && !watching && blockFeed -> "The YouTube feed is paused."
        else -> null
    }

    /** Re-evaluate a completed scan using the live filter state. */
    fun reason(rules: ShieldRules, wallTime: Long, uptime: Long, graceUntil: Long): String? {
        if (uptime < graceUntil || !rules.youtube.any ||
            (rules.youtube.focusOnly && !rules.focusActive(wallTime))) return null
        return reason(rules.youtube.shorts, rules.youtube.feed)
    }
}
