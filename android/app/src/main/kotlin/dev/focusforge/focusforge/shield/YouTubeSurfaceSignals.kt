package dev.focusforge.focusforge.shield

/** Visible, exact resource identities keep home shelves distinct from playback. */
class YouTubeSurfaceSignals {
    private var shorts = false
    private var watching = false
    private var feed = false
    private val creators = mutableSetOf<String>()
    fun observe(resourceId: String?, visible: Boolean, creatorText: String? = null, currentVideoCreator: Boolean = false) {
        if (!visible || resourceId == null ||
            !resourceId.startsWith("com.google.android.youtube:id/")) return
        when (resourceId.substringAfter(":id/")) {
            "reel_recycler", "reel_pager", "reel_watch", "reel_player",
            "reel_progress_bar", "shorts_player" -> shorts = true
            "watch_player", "player_controller", "fullscreen_player" -> watching = true
            "results", "feed_recycler_view", "home_feed", "rich_grid" -> feed = true
            "channel_name", "channel_handle", "owner_name", "channel_title" ->
                if (currentVideoCreator) creatorText?.takeIf { it.length <= 100 }?.let(creators::add)
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
        val surfaceReason = reason(rules.youtube.shorts, rules.youtube.feed)
        if (surfaceReason != null) return surfaceReason
        if (rules.youtube.studyOnly && (watching || shorts) &&
            !StudyChannelPolicy(rules.youtube.studyChannels).allows(creators)) {
            return "Choose a video from your study channels."
        }
        return null
    }
}
