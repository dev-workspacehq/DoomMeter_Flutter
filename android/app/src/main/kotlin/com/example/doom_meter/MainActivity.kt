package com.example.doom_meter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.doom_meter.tracking.ScrollTrackingChannel

class MainActivity : FlutterActivity() {
    private var trackingChannel: ScrollTrackingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        trackingChannel?.dispose()
        trackingChannel = ScrollTrackingChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        trackingChannel?.dispose()
        trackingChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
