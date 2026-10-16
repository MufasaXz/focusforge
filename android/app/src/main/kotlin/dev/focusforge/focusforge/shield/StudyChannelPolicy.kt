package dev.focusforge.focusforge.shield

import java.util.Locale

/** Exact creator recognition stays offline; it does not classify individual videos. */
class StudyChannelPolicy(channels: List<String>) {
    private val selected = (channels.take(100) + knownCreators).mapNotNull(::normalize).toSet()

    fun allows(visibleCreators: Collection<String>): Boolean =
        visibleCreators.any { normalize(it)?.let(selected::contains) == true }

    private fun normalize(value: String): String? {
        val normalized = value.trim().replace(Regex("\\s+"), " ")
        if (normalized.isEmpty() || normalized.length > 100 || normalized.any { it.code < 32 }) return null
        return normalized.lowercase(Locale.ROOT)
    }

    companion object {
        // Exact aliases, independently maintained. Never allow substring matches:
        // a reaction channel or title mentioning a teacher is not that teacher.
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
            "Khan Academy English", "@khanacademyenglish",
            "Mathologer", "@mathologer", "Eddie Woo", "@misterwootube",
            "The Coding Train", "@thecodingtrain", "Corey Schafer", "@coreyms",
            "StatQuest with Josh Starmer", "@statquest", "Sebastian Lague", "@sebastianlague",
            "Ben Eater", "@beneater", "Neso Academy", "@nesoacademy",
            "Gate Smashers", "@gatesmashers", "Jenny's Lectures CS IT", "@jennyslecturescsit",
            "Abdul Bari", "@abdul_bari", "WilliamFiset", "@williamfiset-videos",
            "Harvard University", "@harvard", "Stanford", "@stanford",
            "YaleCourses", "@yalecourses", "The Open University", "@openuniversity",
            "BBC Learning English", "@bbclearningenglish", "British Council | LearnEnglish", "@britishcouncillearnenglish",
            "DW Deutsch lernen", "@dwdeutschlernen", "Easy Languages", "@easylanguages",
            "Les Bons Profs", "@lesbonsprofs", "unicoos", "@unicoos",
            "julioprofe", "@julioprofe", "Khan Academy Brasil", "@khanacademyportugues",
            "Khan Academy Español", "@khanacademyespanol", "Khan Academy Türkçe", "@khanacademyturkce",
            "Apna College", "@apnacollegeofficial", "CodeWithHarry", "@codewithharry",
            "Dr. Trefor Bazett", "@drtrefor", "NancyPi", "@nancypi",
            "PatrickJMT", "@patrickjmt", "The Maths Prof", "@themathsprof",
            "Organic Chemistry Tutor", "@organicchemistrytutor",
            "Bozeman Science", "@bozemanscience", "Tyler DeWitt", "@tdewitt451",
        )
    }
}
