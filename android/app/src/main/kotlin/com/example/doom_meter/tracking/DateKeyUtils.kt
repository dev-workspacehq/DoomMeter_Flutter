package com.example.doom_meter.tracking

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object DateKeyUtils {
    private fun formatter() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        isLenient = false
        timeZone = TimeZone.getDefault()
    }

    fun localDateKey(timestamp: Long): String = formatter().format(Date(timestamp))

    fun isValid(key: String): Boolean {
        if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(key)) return false
        val position = ParsePosition(0)
        // Validate a calendar key independently of the user's current zone;
        // historical records may have been created before travelling.
        val parser = formatter().apply { timeZone = TimeZone.getTimeZone("UTC") }
        return parser.parse(key, position) != null && position.index == key.length
    }
}
