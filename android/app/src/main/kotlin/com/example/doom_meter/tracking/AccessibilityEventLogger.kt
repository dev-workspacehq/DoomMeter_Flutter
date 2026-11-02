package com.example.doom_meter.tracking

import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.example.doom_meter.BuildConfig

/** Local debug diagnostics only. Never log titles, comments, or arbitrary text. */
internal object AccessibilityEventLogger {
    const val TAG = "DoomScrollTracking"
    private val safeControlLabels = setOf("shorts", "like", "dislike", "comments", "share")

    @Suppress("DEPRECATION")
    fun log(event: AccessibilityEvent) {
        if (!BuildConfig.DEBUG) return
        val source = event.source
        try {
            val description = source?.contentDescription?.toString()
            val safeDescription = when {
                description == null -> "null"
                description.lowercase() in safeControlLabels -> description.lowercase()
                else -> "<redacted>"
            }
            val deltas = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                "deltaX=${event.scrollDeltaX} deltaY=${event.scrollDeltaY}"
            } else {
                "deltaX=unavailable deltaY=unavailable"
            }
            Log.d(TAG, "type=${AccessibilityEvent.eventTypeToString(event.eventType)} " +
                "eventTime=${event.eventTime} package=${event.packageName} class=${event.className} " +
                "from=${event.fromIndex} to=${event.toIndex} items=${event.itemCount} " +
                "x=${event.scrollX} y=${event.scrollY} maxX=${event.maxScrollX} maxY=${event.maxScrollY} " +
                "$deltas sourceClass=${source?.className} sourceId=${source?.viewIdResourceName} " +
                "sourceDescription=$safeDescription changeTypes=${event.contentChangeTypes}")
        } finally {
            source?.recycle()
        }
    }
}
