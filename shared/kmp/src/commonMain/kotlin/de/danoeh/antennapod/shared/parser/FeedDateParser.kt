package de.danoeh.antennapod.shared.parser

object FeedDateParser {
    private val months = mapOf(
        "jan" to 1, "feb" to 2, "mar" to 3, "apr" to 4, "may" to 5, "jun" to 6,
        "jul" to 7, "aug" to 8, "sep" to 9, "oct" to 10, "nov" to 11, "dec" to 12,
    )

    fun parseToEpochMs(raw: String?): Long? {
        if (raw.isNullOrBlank()) {
            return null
        }
        val value = raw.trim()
        parseIso8601(value)?.let { return it }
        return parseRfc822(value)
    }

    private fun parseIso8601(value: String): Long? {
        val match = Regex(
            """^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|([+-]\d{2}):?(\d{2}))?$"""
        ).matchEntire(value) ?: return null
        val year = match.groupValues[1].toInt()
        val month = match.groupValues[2].toInt()
        val day = match.groupValues[3].toInt()
        val hour = match.groupValues[4].toInt()
        val minute = match.groupValues[5].toInt()
        val second = match.groupValues[6].toInt()
        val offsetHours = match.groupValues[7].ifBlank { "+00" }.toInt()
        val offsetMinutes = match.groupValues[8].ifBlank { "00" }.toInt()
        val sign = if (offsetHours < 0 || match.groupValues[7].startsWith("-")) -1 else 1
        val offsetTotalMinutes = sign * (kotlin.math.abs(offsetHours) * 60 + offsetMinutes)
        return utcEpochMs(year, month, day, hour, minute, second) - offsetTotalMinutes * 60_000L
    }

    private fun parseRfc822(value: String): Long? {
        val cleaned = value.replace(",", " ").replace(Regex("\\s+"), " ").trim()
        val parts = cleaned.split(" ")
        if (parts.size < 5) {
            return null
        }
        val hasWeekday = parts[0].any { it.isLetter() } && parts[0].length <= 3 && !months.containsKey(parts[1].lowercase())
        val dayIndex = if (hasWeekday) 1 else 0
        if (parts.size < dayIndex + 5) {
            return null
        }
        val day = parts[dayIndex].toIntOrNull() ?: return null
        val month = months[parts[dayIndex + 1].lowercase()] ?: return null
        var year = parts[dayIndex + 2].toIntOrNull() ?: return null
        if (year < 100) {
            year += 1900
        }
        val timeParts = parts[dayIndex + 3].split(":")
        if (timeParts.size < 2) {
            return null
        }
        val hour = timeParts[0].toIntOrNull() ?: return null
        val minute = timeParts[1].toIntOrNull() ?: return null
        val second = timeParts.getOrNull(2)?.toIntOrNull() ?: 0
        val zone = parts[dayIndex + 4]
        val offsetMinutes = parseZoneOffsetMinutes(zone) ?: return null
        return utcEpochMs(year, month, day, hour, minute, second) - offsetMinutes * 60_000L
    }

    private fun parseZoneOffsetMinutes(zone: String): Int? {
        if (zone.equals("UT", true) || zone.equals("GMT", true) || zone.equals("Z", true)) {
            return 0
        }
        val match = Regex("""^([+-])(\d{2}):?(\d{2})$""").matchEntire(zone) ?: return null
        val sign = if (match.groupValues[1] == "-") -1 else 1
        val hours = match.groupValues[2].toInt()
        val minutes = match.groupValues[3].toInt()
        return sign * (hours * 60 + minutes)
    }

    private fun utcEpochMs(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int): Long {
        val days = toEpochDay(year, month, day)
        return ((days * 24L + hour) * 60L + minute) * 60L * 1000L + second * 1000L
    }

    private fun toEpochDay(year: Int, month: Int, day: Int): Long {
        val y = year.toLong()
        val m = month.toLong()
        var total = 0L
        val y0 = y - 1970
        total += y0 * 365
        total += countLeapDays(1969 + y0) - countLeapDays(1969)
        val monthDays = intArrayOf(0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
        for (i in 1 until m.toInt()) {
            total += monthDays[i]
            if (i == 2 && isLeap(y)) {
                total += 1
            }
        }
        total += day - 1
        return total
    }

    private fun countLeapDays(yearInclusive: Long): Long {
        if (yearInclusive < 1) {
            return 0
        }
        return yearInclusive / 4 - yearInclusive / 100 + yearInclusive / 400
    }

    private fun isLeap(year: Long): Boolean {
        return (year % 4 == 0L && year % 100 != 0L) || year % 400 == 0L
    }
}
