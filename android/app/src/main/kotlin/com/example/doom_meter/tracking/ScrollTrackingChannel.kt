package com.example.doom_meter.tracking

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class ScrollTrackingChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val main = Handler(Looper.getMainLooper())
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isAccessibilityTrackingEnabled" -> result.success(AccessibilityUtils.isTrackingEnabled(activity))
                    "openAccessibilitySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "getDetectedDailyCounts" -> ScrollTrackingStore.getInstance(activity).readDailyCounts(
                        onSuccess = { records -> main.post { if (!disposed) result.success(records) } },
                        onError = { main.post { if (!disposed) result.error("tracking_storage", "Could not read native tracking data.", null) } },
                    )
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("tracking_unavailable", "Could not access Android tracking settings.", null)
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.example.doom_meter/scroll_tracking"
    }
}
