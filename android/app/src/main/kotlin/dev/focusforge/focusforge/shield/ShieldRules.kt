package dev.focusforge.focusforge.shield

import android.content.Context
import org.json.JSONObject

/** How hard an app is restricted. */
enum class RuleMode {
    /** Always closed while the rule is in place. */
    BLOCK,

    /** Closed once today's foreground time passes [AppRule.budgetMinutes]. */
    BUDGET;

    companion object {
        fun fromName(name: String?): RuleMode =
            if (name == "budget") BUDGET else BLOCK
    }
}

/** One app the user has asked FocusForge to keep closed. */
data class AppRule(
    val packageName: String,
    val label: String,
    val mode: RuleMode,
    val budgetMinutes: Int,
)

/**
 * The YouTube surface rules.
 *
 * YouTube is the one app where a package-level block is too blunt: the same
 * package holds a lecture and a Shorts feed. These two switches pick the
 * surfaces to close, and everything else in the app keeps working.
 */
data class YoutubeRules(
    val shorts: Boolean,
    val feed: Boolean,
) {
    val any: Boolean get() = shorts || feed

    companion object {
        val OFF = YoutubeRules(shorts = false, feed = false)
    }
}

/**
 * The complete desired shield state, as the service reads it.
 *
 * The service loads this from disk rather than waiting for a channel call, so
 * it keeps working after Android restarts it following a process kill — which
 * is exactly when a user is most likely to notice that blocking has stopped.
 */
data class ShieldRules(
    val apps: Map<String, AppRule>,
    val youtube: YoutubeRules,
    val graceSeconds: Int,
    /**
     * When a Strict Mode window closes, as epoch milliseconds, or null when
     * none is open. While one is open every rule is treated as a full block —
     * a budget the user can spend their way through is not a commitment.
     */
    val strictUntilMillis: Long?,
) {
    fun ruleFor(packageName: String): AppRule? = apps[packageName]

    /** True while a Strict Mode window is open. */
    fun strictModeActive(now: Long): Boolean {
        val until = strictUntilMillis ?: return false
        return now < until
    }

    companion object {
        val EMPTY = ShieldRules(
            apps = emptyMap(),
            youtube = YoutubeRules.OFF,
            graceSeconds = DEFAULT_GRACE_SECONDS,
            strictUntilMillis = null,
        )

        /**
         * Fallback only. The live value is written by the Dart side and arrives
         * in [parse]; this is what the service uses before the app has ever
         * pushed a config.
         */
        const val DEFAULT_GRACE_SECONDS = 300

        /**
         * Reads the payload the Dart side wrote.
         *
         * Every field is defaulted rather than cast. This runs on the
         * accessibility service's own thread during `onServiceConnected`, and a
         * schema-broken value must degrade to "block nothing" rather than throw
         * and take the service down with it.
         */
        fun parse(raw: String?): ShieldRules {
            if (raw.isNullOrBlank()) return EMPTY
            return try {
                val root = JSONObject(raw)

                val apps = LinkedHashMap<String, AppRule>()
                root.optJSONObject("apps")?.let { map ->
                    for (key in map.keys()) {
                        val row = map.optJSONObject(key) ?: continue
                        if (key.isBlank()) continue
                        apps[key] = AppRule(
                            packageName = key,
                            label = row.optString("label", key),
                            mode = RuleMode.fromName(row.optString("mode", "block")),
                            budgetMinutes = row.optInt("budgetMinutes", 0),
                        )
                    }
                }

                val yt = root.optJSONObject("youtube")
                val youtube = YoutubeRules(
                    shorts = yt?.optBoolean("shorts", false) ?: false,
                    feed = yt?.optBoolean("feed", false) ?: false,
                )

                // `optLong` returns 0 for an absent key, which would read as a
                // window that closed in 1970 rather than one that never opened.
                val strict = if (root.has("strictUntil") && !root.isNull("strictUntil")) {
                    root.optLong("strictUntil", 0L).takeIf { it > 0L }
                } else {
                    null
                }

                ShieldRules(
                    apps = apps,
                    youtube = youtube,
                    graceSeconds = root.optInt(
                        "graceSeconds",
                        DEFAULT_GRACE_SECONDS,
                    ).coerceIn(5, 600),
                    strictUntilMillis = strict,
                )
            } catch (_: Exception) {
                EMPTY
            }
        }
    }
}

/**
 * Where the rules live on the device.
 *
 * A dedicated preferences file, written by [ShieldBridge] and read by
 * [FocusAccessibilityService]. Neither side holds a reference to the other:
 * the service outlives the Flutter engine, and must be able to rebuild its
 * whole world from disk.
 */
object ShieldStore {
    private const val PREFS = "focusforge_shield"
    private const val KEY_RULES = "rules"

    fun load(context: Context): ShieldRules =
        ShieldRules.parse(
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_RULES, null),
        )

    fun save(context: Context, rules: ShieldRules) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RULES, encode(rules))
            .apply()
    }

    /** The wire format, shared with the Dart side's payload. */
    fun encode(rules: ShieldRules): String {
        val apps = JSONObject()
        for ((packageName, rule) in rules.apps) {
            apps.put(
                packageName,
                JSONObject()
                    .put("label", rule.label)
                    .put("mode", if (rule.mode == RuleMode.BUDGET) "budget" else "block")
                    .put("budgetMinutes", rule.budgetMinutes),
            )
        }
        return JSONObject()
            .put("apps", apps)
            .put(
                "youtube",
                JSONObject()
                    .put("shorts", rules.youtube.shorts)
                    .put("feed", rules.youtube.feed),
            )
            .put("strictUntil", rules.strictUntilMillis ?: JSONObject.NULL)
            .put("graceSeconds", rules.graceSeconds)
            .toString()
    }
}
