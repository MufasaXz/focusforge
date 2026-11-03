package dev.focusforge.focusforge.shield

import java.util.Locale

/**
 * Decides whether a YouTube video belongs to Study mode, entirely on the phone.
 *
 * A channel matches exactly — by name or @handle — against the user's study
 * channels and a bundled list of well-known educational creators. Never by
 * substring: a reaction channel whose name contains a teacher's is not that
 * teacher. A title matches when it contains one of the user's keywords (their
 * subject names, or words they added) as a whole word.
 */
class StudyChannelPolicy(channels: List<String>, keywords: List<String>) {
    private val selected = (channels.take(100) + knownCreators).mapNotNull(::normalize).toSet()
    private val words = keywords.take(50).mapNotNull(::normalize).filter { it.length >= 3 }

    fun allowsChannel(name: String?, handle: String?): Boolean =
        listOfNotNull(name, handle).any { candidate ->
            val normalized = normalize(candidate) ?: return@any false
            normalized in selected ||
                normalized.removePrefix("@") in selected ||
                "@$normalized" in selected
        }

    fun allowsTitle(texts: Collection<String>): Boolean {
        if (words.isEmpty()) return false
        return texts.any { text ->
            val lower = text.lowercase(Locale.ROOT)
            words.any { word -> Regex("(^|\\W)" + Regex.escape(word) + "(\\W|$)").containsMatchIn(lower) }
        }
    }

    companion object {
        fun normalize(value: String): String? {
            val normalized = value.trim().replace(Regex("\\s+"), " ")
            if (normalized.isEmpty() || normalized.length > 100 || normalized.any { it.code < 32 }) return null
            return normalized.lowercase(Locale.ROOT)
        }

        // Exact aliases, independently maintained.
        private val knownCreators = listOf(
            "Khan Academy", "@khanacademy", "Khan Academy India", "@khanacademyindia",
            "3Blue1Brown", "@3blue1brown", "Numberphile", "@numberphile",
            "Computerphile", "@computerphile", "MIT OpenCourseWare", "@mitocw",
            "freeCodeCamp.org", "@freecodecamp", "CS50", "@cs50",
            "NPTEL", "@nptelhrd", "NPTEL-NOC IITM", "@nptelnociitm9240",
            "CrashCourse", "@crashcourse", "TED-Ed", "@teded",
            "The Organic Chemistry Tutor", "@theorganicchemistrytutor",
            "Professor Dave Explains", "@professordaveexplains",
            "Physics Wallah - Alakh Pandey", "@physicswallah",
            "Magnet Brains", "@magnetbrainseducation", "@magnetbrainseducationhindi",
            "Amoeba Sisters", "@amoebasisters", "Cognito", "@cognitoedu",
            "Mathologer", "@mathologer", "Eddie Woo", "@misterwootube",
            "The Coding Train", "@thecodingtrain", "Corey Schafer", "@coreyms",
            "StatQuest with Josh Starmer", "@statquest", "Sebastian Lague", "@sebastianlague",
            "Ben Eater", "@beneater", "Neso Academy", "@nesoacademy",
            "Gate Smashers", "@gatesmashers", "Jenny's Lectures CS IT", "@jennyslecturescsit",
            "Abdul Bari", "@abdul_bari", "Harvard University", "@harvard", "Stanford", "@stanford",
            "YaleCourses", "@yalecourses", "BBC Learning English", "@bbclearningenglish",
            "DW Deutsch lernen", "@dwdeutschlernen", "Easy Languages", "@easylanguages",
            "Khan Academy Español", "@khanacademyespanol", "Khan Academy Brasil", "@khanacademyportugues",
            "Apna College", "@apnacollegeofficial", "CodeWithHarry", "@codewithharry",
            "Dr. Trefor Bazett", "@drtrefor", "NancyPi", "@nancypi", "PatrickJMT", "@patrickjmt",
            "Bozeman Science", "@bozemanscience", "Tyler DeWitt", "@tdewitt451",
            "Unacademy JEE", "@unacademyjee", "Vedantu JEE", "@vedantujee",
            "Vedantu 9 & 10", "@vedantu9and10", "Physics Wallah Foundation", "@pwfoundation",
            "Dear Sir", "@dearsir", "Study IQ education", "@studyiqeducation",
            "Veritasium", "@veritasium", "Kurzgesagt – In a Nutshell", "@kurzgesagt",
            "SciShow", "@scishow", "minutephysics", "@minutephysics",
            "Fireship", "@fireship", "Traversy Media", "@traversymedia",
        )
    }
}
