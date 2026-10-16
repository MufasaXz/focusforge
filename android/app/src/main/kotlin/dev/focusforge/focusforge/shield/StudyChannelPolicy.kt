package dev.focusforge.focusforge.shield

import java.util.Locale

/** A device-local creator allowlist. It makes no claim about a video's subject. */
class StudyChannelPolicy(channels: List<String>) {
    private val selected = channels.take(100).mapNotNull(::normalize).toSet()

    fun allows(visibleCreators: Collection<String>): Boolean =
        visibleCreators.any { normalize(it)?.let(selected::contains) == true }

    private fun normalize(value: String): String? {
        val normalized = value.trim().replace(Regex("\\s+"), " ")
        if (normalized.isEmpty() || normalized.length > 100 || normalized.any { it.code < 32 }) return null
        return normalized.lowercase(Locale.ROOT)
    }
}
