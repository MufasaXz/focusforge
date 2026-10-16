package dev.focusforge.focusforge.localization

import android.content.Context
import dev.focusforge.focusforge.R

/** Offline copy selected by Android from the phone language list. */
object DeviceStrings {
    private val resources = mapOf(
        "Focus timer" to R.string.ff_copy_662abe203e24,
        "Your running focus or break countdown" to R.string.ff_copy_69a90c89d741,
        "Short break" to R.string.ff_copy_59a006c126ce,
        "Long break" to R.string.ff_copy_2e404536a97f,
        "Focus" to R.string.ff_copy_9d3cab2b5efe,
        "Time for yourself" to R.string.ff_copy_a4ade89a878b,
        "FocusForge timer" to R.string.ff_copy_2acc91c6d64d,
        "Unlock to see your timer details" to R.string.ff_copy_8a1715ff1221,
        "Tap to open your timer" to R.string.ff_copy_5c2f75a5e092,
        "Choose a subject" to R.string.ff_copy_bc85d3b68467,
        "Set a goal in FocusForge" to R.string.ff_copy_af2b2ab96f47,
        "Rest week · No target" to R.string.ff_copy_db73b5af1d5e,
        "Rest day · No target" to R.string.ff_copy_e158f8595efd,
        "this week" to R.string.ff_copy_7d76655e727c,
        "today" to R.string.ff_copy_e0f4f767ac88,
        "WEEKLY GOAL" to R.string.ff_copy_cbde8d2eab34,
        "TODAY’S GOAL" to R.string.ff_copy_952a80b39aae,
        "YOUR NEXT SESSION" to R.string.ff_copy_eb69bb1c4acb,
        "Tap to plan your subjects" to R.string.ff_copy_74088f496014,
        "Take your time · Tap to view" to R.string.ff_copy_7f53b61b0e4a,
        "Goal complete · Keep growing" to R.string.ff_copy_085941b4e4b0,
        "Block ended · Open to continue" to R.string.ff_copy_1fdd668027e9,
        "Ready when you are · Tap to focus" to R.string.ff_copy_39dfdb4e10a4,
        "No study target" to R.string.ff_copy_a9ee6e15ea2b,
        "Your first block starts the week" to R.string.ff_copy_d0f80a75cd2b,
        "Mon – Sun · Tap to view" to R.string.ff_copy_85277319d88a,
        "Focusing · {0}" to R.string.ff_copy_ef961edeef38,
        "{0} · Recharge" to R.string.ff_copy_ca1fc1e14b7a,
        "Monday" to R.string.ff_copy_6a00dfc1dc86,
        "Tuesday" to R.string.ff_copy_7d8af1de1262,
        "Wednesday" to R.string.ff_copy_c0a6cc829cd0,
        "Thursday" to R.string.ff_copy_fc2662062ffd,
        "Friday" to R.string.ff_copy_e21f3f372a46,
        "Saturday" to R.string.ff_copy_dbe35c7363c2,
        "Sunday" to R.string.ff_copy_873fef760e5d,
        "Mon" to R.string.ff_copy_f40d7f51f69e,
        "Tue" to R.string.ff_copy_d1eb39b09bf5,
        "Wed" to R.string.ff_copy_58339f45df96,
        "Thu" to R.string.ff_copy_7da11212ed34,
        "Fri" to R.string.ff_copy_66dab40cea1d,
        "Sat" to R.string.ff_copy_fdeb71b569e0,
        "Sun" to R.string.ff_copy_db18f17fe532,
        "{0} / {1} min {2}" to R.string.ff_copy_09f661ddb4a9,
        "{0} / {1} min" to R.string.ff_copy_9177524bf42c,
        "{0} completed sessions" to R.string.ff_copy_cc627ad2ab67,
        "{0} focused today" to R.string.ff_copy_d1d4a90d7332,
        "{0} min to grow · Tap to view" to R.string.ff_copy_fb129873e871,
        "{0} in progress · Tap to open" to R.string.ff_copy_3e51dc8cd5da,
        "{0} percent of your goal {1} complete" to R.string.ff_copy_37a095ea9890,
        "{0} / 7 days" to R.string.ff_copy_ceab99c54acc,
        "{0} {1} minutes" to R.string.ff_copy_be94370016a8,
        "This week, {0} of completed focus, {1} active days. Today is {2}. {3}. Tap to open your dashboard." to R.string.ff_copy_6e0a11779f21,
        "{0} IN PROGRESS" to R.string.ff_copy_02d6a83a357c,
        "{0} active days" to R.string.ff_copy_16d30c8585e0,
        "THIS WEEK" to R.string.ff_copy_7192a603df72,
        "Stay with your focus" to R.string.ff_copy_52ae6350b671,
        "Need access? Pause and breathe first." to R.string.ff_copy_b9d8f4dfd461,
        "Paused until Strict Mode ends." to R.string.ff_copy_70e87c490114,
        "You chose to pause this app." to R.string.ff_copy_e23c9c6c45ab,
        "Paused during your focus session." to R.string.ff_copy_22f28ebe11d4,
        "You have used your {0} minutes for today." to R.string.ff_copy_2f1be85c9e0c,
        "Shorts are paused. Keep your focus." to R.string.ff_copy_a0f82cce66c4,
        "The YouTube feed is paused." to R.string.ff_copy_88ccdcfb48eb,
        "Choose a video from your study channels." to R.string.ff_copy_b46fd04e8e05,
        "App boundaries" to R.string.ff_copy_d966b84456c7,
        "Visible while your selected apps are being paused. Stop pauses app boundaries." to R.string.ff_copy_a4faac0f2298,
        "FocusForge app boundaries are active" to R.string.ff_copy_ca8c9b42a375,
        "Your chosen apps are paused on this device. Tap Stop to pause boundaries." to R.string.ff_copy_f6463dc9b220,
        "Stop" to R.string.ff_copy_cae7d57bc067,
        "REMAINING" to R.string.ff_copy_59779ce0db49,
        "{0}h" to R.string.ff_copy_360a8af5a7d2,
        "{0}m" to R.string.ff_copy_7f5ea983858e,
        "{0}h {1}m" to R.string.ff_copy_d426ce3b6441,
        "Back to what matters" to R.string.ff_copy_7a73eaec12da,
        "Pause and breathe" to R.string.ff_copy_8cdd22e2e381,
        "Optional YouTube Shorts, feed and study-channel filters." to R.string.ff_copy_5b992ee5fc37,
        "FocusForge checks YouTube screen identifiers only when you enable Shorts or feed filters, to distinguish these screens from ordinary videos. When Study channels only is enabled, visible creator names or handles on supported video pages are compared with channels you selected. Screen checks stay on your device and visible labels are not retained or uploaded. While a YouTube pause is visible, application window package names are checked only to close the pause when you leave; other apps’ contents are not inspected. It does not read messages, passwords or text you type. Pause decisions and their times are saved only on this device for Shield insights. Access is optional and can be turned off in Android Settings. Normal app boundaries use Usage access and Draw over other apps; the focus timer works without any of these." to R.string.ff_copy_da8322cb20a3,
        "A retro countdown and today’s completed focus time. Tap to open Focus." to R.string.ff_copy_83547161198a,
        "Your daily focus goal, completion ring and remaining minutes." to R.string.ff_copy_0a2b0fed0257,
        "Current study subject, live countdown and daily progress." to R.string.ff_copy_0f37116ca951,
        "Completed focus time from Monday to Sunday, weekly total and active days. Tap to open your dashboard." to R.string.ff_copy_7c71b77df96c,
    )
    private val slot = Regex("\\{(\\d+)\\}")
    fun text(context: Context, source: String, vararg values: Any?): String {
        val copy = resources[source]?.let { context.getString(it) } ?: source
        return slot.replace(copy) { match ->
            values.getOrNull(match.groupValues[1].toInt())?.toString() ?: match.value
        }
    }

    fun reason(context: Context, source: String): String {
        val budget = Regex("You have used your (\\d+) minutes for today\\.").matchEntire(source)
        return if (budget != null) text(context, "You have used your {0} minutes for today.", budget.groupValues[1])
            else text(context, source)
    }
}
