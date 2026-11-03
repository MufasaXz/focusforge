package dev.focusforge.focusforge.shield

/**
 * What one walk of YouTube's window found.
 *
 * Surfaces are told apart by YouTube's own view ids. Study mode also reads,
 * from the top of a video page only, the channel name (the "Subscribe to …"
 * button's description), the @handle and the visible text near the player,
 * which holds the title. None of it is kept beyond this one decision.
 */
class YouTubeSurfaceSignals {
    private var shorts = false
    private var watching = false
    private var feed = false
    private var channel: String? = null
    private var handle: String? = null
    private val texts = ArrayList<String>()

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

    /**
     * Text from one visible node near the top of the page. Only called while
     * Study mode is on; [text] and [description] are the node's own labels.
     */
    fun observeText(text: String?, description: String?) {
        description?.let { desc ->
            if (channel == null) {
                subscribe.find(desc.trim())?.let { channel = it.groupValues[2].trim() }
            }
        }
        text?.trim()?.let { value ->
            if (handle == null && value.startsWith("@") && value.length in 3..40 &&
                value.none { it.isWhitespace() }) {
                handle = value
            }
            if (texts.size < MAX_TEXTS && value.length in 3..150) texts.add(value)
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
        reason(rules.youtube.shorts || rules.youtube.study, rules.youtube.feed)?.let { return it }
        return studyReason(rules.youtube)
    }

    /**
     * Study mode's verdict on a video page. Nothing is decided until the
     * channel can be named: an unidentified page is left alone rather than
     * closed on a guess, and the service looks again a moment later.
     */
    private fun studyReason(youtube: YoutubeRules): String? {
        if (!youtube.study || !watching) return null
        val policy = StudyChannelPolicy(youtube.studyChannels, youtube.studyKeywords)
        if (policy.allowsChannel(channel, handle) || policy.allowsTitle(texts)) return null
        if (channel == null && handle == null) return null
        return "Choose a video from your study channels."
    }

    companion object {
        private const val MAX_TEXTS = 40

        // "Subscribe to X." and, once subscribed, "Unsubscribe from X."
        private val subscribe = Regex("(?i)^(subscribe to|unsubscribe from) (.+?)\\.?$")
    }
}
