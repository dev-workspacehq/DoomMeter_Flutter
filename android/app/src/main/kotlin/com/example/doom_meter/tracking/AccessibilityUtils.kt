package com.example.doom_meter.tracking

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.view.accessibility.AccessibilityManager

internal object AccessibilityUtils {
    fun isTrackingEnabled(context: Context): Boolean {
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val target = ComponentName(context, ScrollAccessibilityService::class.java)
        return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any {
            val service = it.resolveInfo.serviceInfo
            ComponentName(service.packageName, service.name) == target
        }
    }
}
