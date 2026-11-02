package com.example.doom_meter.tracking

/** Structural metadata only; no video text or identifiers are retained. */
internal data class ShortsViewerSnapshot(
    val session: String,
    val row: Int?,
    val blocked: Boolean = false,
)

internal enum class ScrollDirection { FORWARD, BACKWARD, UNKNOWN }

internal enum class TransitionDecision {
    COUNT,
    IGNORE_BACKWARD,
    IGNORE_UNKNOWN_DIRECTION,
    IGNORE_DUPLICATE,
    IGNORE_REVISITED_POSITION,
    IGNORE_DEBOUNCE,
    IGNORE_NOT_SHORTS,
}

internal data class ShortsTransitionResult(
    val fromRow: Int?,
    val toRow: Int?,
    val direction: ScrollDirection,
    val decision: TransitionDecision,
)

/** Compare settled collection rows, not event fromIndex/toIndex or delta signs. */
internal fun detectScrollDirection(fromRow: Int?, toRow: Int?): ScrollDirection = when {
    fromRow == null || toRow == null || fromRow < 0 || toRow < 0 -> ScrollDirection.UNKNOWN
    toRow > fromRow -> ScrollDirection.FORWARD
    toRow < fromRow -> ScrollDirection.BACKWARD
    else -> ScrollDirection.UNKNOWN
}

/** Pure state machine, independent of AccessibilityService and persistence. */
internal class ShortsTransitionDetector {
    private var session: String? = null
    private var previousRow: Int? = null
    // A positional boundary within one uninterrupted viewer, NOT a video ID.
    private var highestObservedRow: Int? = null
    private var lastCountedAt: Long? = null

    fun observe(snapshot: ShortsViewerSnapshot?, elapsedTime: Long): ShortsTransitionResult {
        if (snapshot == null || snapshot.blocked) {
            reset()
            return ShortsTransitionResult(null, snapshot?.row, ScrollDirection.UNKNOWN, TransitionDecision.IGNORE_NOT_SHORTS)
        }
        if (session != snapshot.session) {
            reset()
            session = snapshot.session
        }
        // During animations there may be no single fully visible page.
        val previous = previousRow
        val row = snapshot.row?.takeIf { it >= 0 }
        val direction = detectScrollDirection(previous, row)
        fun result(decision: TransitionDecision) = ShortsTransitionResult(previous, row, direction, decision)
        if (row == null) return result(TransitionDecision.IGNORE_UNKNOWN_DIRECTION)
        previousRow = row
        val highest = highestObservedRow
        highestObservedRow = maxOf(highest ?: row, row)
        // Entering/re-entering a viewer establishes a baseline, not a scroll.
        if (previous == null) return result(TransitionDecision.IGNORE_UNKNOWN_DIRECTION)
        if (previous == row) return result(TransitionDecision.IGNORE_DUPLICATE)
        // Backward movement updates the comparison row, never the count or timestamp.
        if (direction == ScrollDirection.BACKWARD) return result(TransitionDecision.IGNORE_BACKWARD)
        if (direction != ScrollDirection.FORWARD) return result(TransitionDecision.IGNORE_UNKNOWN_DIRECTION)
        // Conservatively suppress positions in the already traversed range. This also
        // excludes skipped/debounced rows when retracing; never backfill missed counts.
        if (highest != null && row <= highest) return result(TransitionDecision.IGNORE_REVISITED_POSITION)
        val last = lastCountedAt
        if (last != null && elapsedTime - last < SCROLL_DEBOUNCE_MS) return result(TransitionDecision.IGNORE_DEBOUNCE)
        lastCountedAt = elapsedTime
        return result(TransitionDecision.COUNT)
    }

    fun reset() {
        session = null
        previousRow = null
        highestObservedRow = null
        lastCountedAt = null
    }

    companion object {
        // Tune from device measurements. Distinct transitions inside this
        // interval can be missed; repeated row values are rejected at any age.
        const val SCROLL_DEBOUNCE_MS = 600L
    }
}
