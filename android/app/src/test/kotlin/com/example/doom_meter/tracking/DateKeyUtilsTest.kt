package com.example.doom_meter.tracking

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class DateKeyUtilsTest {
    @Test fun localMidnightCreatesANewKeyWithoutResettingAnything() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kolkata"))
            val calendar = Calendar.getInstance().apply {
                clear()
                set(2026, Calendar.OCTOBER, 31, 23, 59, 59)
            }
            val timestamp = calendar.timeInMillis
            assertEquals("2026-10-31", DateKeyUtils.localDateKey(timestamp))
            assertEquals("2026-11-01", DateKeyUtils.localDateKey(timestamp + 1000))
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            assertEquals("2026-10-31", DateKeyUtils.localDateKey(timestamp + 1000))
        } finally { TimeZone.setDefault(original) }
    }

    @Test fun invalidDatesAreRejected() {
        assertTrue(DateKeyUtils.isValid("2026-11-01"))
        assertTrue(DateKeyUtils.isValid("2028-02-29"))
        for (key in listOf("2026-02-29", "2026-13-01", "2026-11-01junk", "2026-1-1", "0000-01-01")) {
            assertFalse(key, DateKeyUtils.isValid(key))
        }
    }

    @Test fun historicalKeyValidityDoesNotDependOnCurrentTimeZone() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Pacific/Apia"))
            assertTrue(DateKeyUtils.isValid("2011-12-30"))
        } finally { TimeZone.setDefault(original) }
    }
}
