package com.example.doom_meter.tracking

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.example.doom_meter.BuildConfig

class ScrollAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val detector = ShortsTransitionDetector()
    private var samplePending = false
    private val sample = Runnable {
        samplePending = false
        inspectViewer()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.packageName?.toString() != YOUTUBE_PACKAGE) return
        if (BuildConfig.DEBUG) AccessibilityEventLogger.log(event)
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> if (!samplePending) {
                // Event-triggered coalescing, not continuous background polling.
                samplePending = true
                handler.postDelayed(sample, SAMPLE_DELAY_MS)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun inspectViewer() {
        val root = rootInActiveWindow
        try {
            val display = resources.displayMetrics
            val snapshot = YouTubeShortsViewerReader.read(root, display.widthPixels, display.heightPixels)
            val transition = detector.observe(snapshot, SystemClock.elapsedRealtime())
            if (BuildConfig.DEBUG) {
                Log.d(AccessibilityEventLogger.TAG,
                    "shortsViewer=${snapshot != null} blocked=${snapshot?.blocked ?: false} " +
                        "fromRow=${transition.fromRow} toRow=${transition.toRow} direction=${transition.direction} " +
                        "duplicate=${transition.decision == TransitionDecision.IGNORE_DUPLICATE} " +
                        "revisit=${transition.decision == TransitionDecision.IGNORE_REVISITED_POSITION} " +
                        "action=${transition.decision}")
            }
            if (transition.decision == TransitionDecision.COUNT) {
                ScrollTrackingStore.getInstance(this).incrementYouTube(System.currentTimeMillis()) {
                    Log.e(AccessibilityEventLogger.TAG, "Native tracking write failed")
                }
            }
        } catch (_: Exception) {
            detector.reset()
            if (BuildConfig.DEBUG) Log.d(AccessibilityEventLogger.TAG, "Viewer snapshot unavailable")
        } finally {
            root?.recycle()
        }
    }

    override fun onInterrupt() {
        clearPendingSample()
        if (BuildConfig.DEBUG) Log.d(AccessibilityEventLogger.TAG, "Service interrupted")
    }

    override fun onDestroy() {
        clearPendingSample()
        super.onDestroy()
    }

    private fun clearPendingSample() {
        handler.removeCallbacks(sample)
        samplePending = false
        detector.reset()
    }

    companion object {
        const val YOUTUBE_PACKAGE = "com.google.android.youtube"
        private const val SAMPLE_DELAY_MS = 80L
    }
}
