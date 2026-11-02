package com.example.doom_meter.tracking

/** Structural metadata only; no video text or identifiers are retained. */
internal data class ShortsViewerSnapshot(
    val session: String,
    val row: Int?,
    val blocked: Boolean = false,
)

internal data class ShortsTransition(val fromRow: Int, val toRow: Int) {
    val direction: String get() = if (toRow > fromRow) "next" else "previous"
}

/** Pure state machine, independent of AccessibilityService and persistence. */
internal class ShortsTransitionDetector {
    private var session: String? = null
    private var previousRow: Int? = null
    private var lastCountedAt: Long? = null

    fun observe(snapshot: ShortsViewerSnapshot?, elapsedTime: Long): ShortsTransition? {
        if (snapshot == null || snapshot.blocked) {
            reset()
            return null
        }
        if (session != snapshot.session) {
            reset()
            session = snapshot.session
        }
        // During animations there may be no single fully visible page.
        val row = snapshot.row?.takeIf { it >= 0 } ?: return null
        val previous = previousRow
        previousRow = row
        // Entering/re-entering a viewer establishes a baseline, not a scroll.
        if (previous == null || previous == row) return null
        val last = lastCountedAt
        if (last != null && elapsedTime - last < SCROLL_DEBOUNCE_MS) return null
        lastCountedAt = elapsedTime
        return ShortsTransition(previous, row)
    }

    fun reset() {
        session = null
        previousRow = null
        lastCountedAt = null
    }

    companion object {
        // Tune from device measurements. Distinct transitions inside this
        // interval can be missed; repeated row values are rejected at any age.
        const val SCROLL_DEBOUNCE_MS = 600L
    }
}
