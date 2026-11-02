package com.example.doom_meter.tracking

import android.content.Context
import android.content.SharedPreferences
import java.util.concurrent.Executors

/** One process-wide queue serializes durable increments and reads, even across Activity recreation. */
internal class ScrollTrackingStore private constructor(private val preferences: SharedPreferences) {
    private val queue = Executors.newSingleThreadExecutor()
    private var writeFailure: Exception? = null

    fun incrementYouTube(timestamp: Long, onError: (Exception) -> Unit) {
        // Capture the date before queuing, so a midnight/timezone change does not move the event.
        val date = DateKeyUtils.localDateKey(timestamp)
        queue.execute {
            try {
                val current = preferences.getLong(COUNT_PREFIX + date, 0)
                check(current >= 0 && current < Long.MAX_VALUE) { "Invalid stored count" }
                check(preferences.edit()
                    .putLong(COUNT_PREFIX + date, current + 1)
                    .putLong(TIME_PREFIX + date, timestamp)
                    .commit()) { "Native tracking write failed" }
                writeFailure = null
            } catch (error: Exception) {
                writeFailure = error
                onError(error)
            }
        }
    }

    fun readDailyCounts(onSuccess: (List<Map<String, Any?>>) -> Unit, onError: (Exception) -> Unit) {
        queue.execute {
            try {
                writeFailure?.let { throw it }
                val values = preferences.all
                val records = values.keys.filter { it.startsWith(COUNT_PREFIX) }.sorted().map { key ->
                    val date = key.removePrefix(COUNT_PREFIX)
                    check(DateKeyUtils.isValid(date)) { "Invalid stored date" }
                    val count = values[key] as? Long ?: error("Invalid stored count")
                    check(count >= 0) { "Negative stored count" }
                    val rawTime = values[TIME_PREFIX + date]
                    val timestamp = if (rawTime == null) null else rawTime as? Long ?: error("Invalid stored time")
                    check(timestamp == null || timestamp >= 0) { "Invalid stored time" }
                    mapOf<String, Any?>("date" to date, "youtubeCount" to count, "lastActivityAt" to timestamp)
                }
                onSuccess(records)
            } catch (error: Exception) {
                onError(error)
            }
        }
    }

    companion object {
        private const val COUNT_PREFIX = "youtube_count_"
        private const val TIME_PREFIX = "youtube_last_activity_"
        private var instance: ScrollTrackingStore? = null

        @Synchronized
        fun getInstance(context: Context): ScrollTrackingStore = instance ?: ScrollTrackingStore(
            context.applicationContext.getSharedPreferences("scroll_tracking", Context.MODE_PRIVATE)
        ).also { instance = it }
    }
}
