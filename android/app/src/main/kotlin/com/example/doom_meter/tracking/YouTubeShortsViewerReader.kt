package com.example.doom_meter.tracking

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/** IDs and collection rows observed on YouTube 21.34.243; intentionally conservative. */
internal object YouTubeShortsViewerReader {
    @Suppress("DEPRECATION")
    fun read(root: AccessibilityNodeInfo?, displayWidth: Int, displayHeight: Int): ShortsViewerSnapshot? {
        if (root?.packageName?.toString() != ScrollAccessibilityService.YOUTUBE_PACKAGE) return null
        val owned = mutableListOf<AccessibilityNodeInfo>()
        fun nodes(id: String): List<AccessibilityNodeInfo> =
            root.findAccessibilityNodeInfosByViewId("${ScrollAccessibilityService.YOUTUBE_PACKAGE}:id/$id")
                .also { owned.addAll(it) }
        fun bounds(node: AccessibilityNodeInfo) = Rect().also(node::getBoundsInScreen)
        try {
            val viewer = nodes("reel_watch_fragment_root").firstOrNull { it.isVisibleToUser } ?: return null
            val recycler = nodes("reel_recycler").firstOrNull { it.isVisibleToUser } ?: return null
            val viewport = bounds(recycler)
            val window = bounds(root)
            // Exclude mini-players, collapsed panels, and most picture-in-picture windows.
            if (viewport.height() < window.height() * 0.65 || viewport.width() < window.width() * 0.8 ||
                viewport.height() < displayHeight * 0.5 || viewport.width() < displayWidth * 0.65) return null
            val blocked = nodes("results").any { it.isVisibleToUser } ||
                nodes("watch_list").any { it.isVisibleToUser }
            val pages = nodes("reel_player_page_container").filter { page ->
                val rect = bounds(page)
                page.isVisibleToUser && rect.height() > 0 &&
                    kotlin.math.abs(rect.top - viewport.top) <= viewport.height() * 0.03 &&
                    kotlin.math.abs(rect.bottom - viewport.bottom) <= viewport.height() * 0.03
            }
            // Never guess from text, a generic scroll delta, or an unknown row.
            val row = pages.singleOrNull()?.collectionItemInfo?.rowIndex?.takeIf { it >= 0 }
            return ShortsViewerSnapshot("${viewer.windowId}:${recycler.hashCode()}", row, blocked)
        } finally {
            owned.forEach { it.recycle() }
        }
    }
}
