package com.example.doom_meter.tracking

import org.junit.Assert.*
import org.junit.Test

class ShortsTransitionDetectorTest {
    private fun page(row: Int?, session: String = "viewer") = ShortsViewerSnapshot(session, row)
    private fun assertDecision(expected: TransitionDecision, result: ShortsTransitionResult) =
        assertEquals(expected, result.decision)

    @Test fun directionUsesSettledRowsAndRejectsAmbiguity() {
        assertEquals(ScrollDirection.FORWARD, detectScrollDirection(11, 12))
        assertEquals(ScrollDirection.BACKWARD, detectScrollDirection(12, 11))
        for ((from, to) in listOf(null to 1, 1 to null, -1 to 1, 1 to -1, 1 to 1)) {
            assertEquals(ScrollDirection.UNKNOWN, detectScrollDirection(from, to))
        }
    }

    @Test fun entryAndRepeatedEventsNeverCount() {
        val detector = ShortsTransitionDetector()
        assertDecision(TransitionDecision.IGNORE_NOT_SHORTS, detector.observe(null, 0))
        assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(11), 100))
        for (time in listOf(200L, 500L, 900L, 5000L)) {
            assertDecision(TransitionDecision.IGNORE_DUPLICATE, detector.observe(page(11), time))
        }
    }

    @Test fun tenNewForwardRowsCountTenTimes() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        for (row in 1..10) {
            val result = detector.observe(page(row), row * 1000L)
            assertDecision(TransitionDecision.COUNT, result)
            assertEquals(ScrollDirection.FORWARD, result.direction)
            assertEquals(row - 1, result.fromRow)
            assertEquals(row, result.toRow)
        }
    }

    @Test fun fiveBackwardRowsNeverCount() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(10), 0)
        for (row in 9 downTo 5) {
            val result = detector.observe(page(row), (10 - row) * 1000L)
            assertDecision(TransitionDecision.IGNORE_BACKWARD, result)
            assertEquals(ScrollDirection.BACKWARD, result.direction)
        }
    }

    @Test fun alternatingSameTwoPositionsCountsOnlyTheFirstDiscovery() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertDecision(TransitionDecision.COUNT, detector.observe(page(1), 1000))
        for (cycle in 1..3) {
            assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(0), cycle * 2000L))
            assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(1), cycle * 2000L + 1000))
        }
    }

    @Test fun retracingHistoryOnlyCountsWhenPassingPreviousHighestPosition() {
        val detector = ShortsTransitionDetector()
        val rows = listOf(0, 1, 2, 3, 2, 1, 2, 3, 4)
        val decisions = rows.mapIndexed { index, row -> detector.observe(page(row), index * 1000L).decision }
        assertEquals(listOf(
            TransitionDecision.IGNORE_UNKNOWN_DIRECTION,
            TransitionDecision.COUNT, TransitionDecision.COUNT, TransitionDecision.COUNT,
            TransitionDecision.IGNORE_BACKWARD, TransitionDecision.IGNORE_BACKWARD,
            TransitionDecision.IGNORE_REVISITED_POSITION, TransitionDecision.IGNORE_REVISITED_POSITION,
            TransitionDecision.COUNT,
        ), decisions)
    }

    @Test fun goingBelowInitialPositionDoesNotTurnEntryIntoDiscovery() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(5), 0)
        assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(3), 1000))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(4), 2000))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(5), 3000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(6), 4000))
    }

    @Test fun animationWithoutASettledPagePreservesHistory() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertDecision(TransitionDecision.COUNT, detector.observe(page(1), 1000))
        assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(null), 1500))
        assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(0), 2000))
        detector.observe(page(null), 2500)
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(1), 3000))
    }

    @Test fun blockedPanelsAndViewerExitResetTheContext() {
        for (interruption in listOf(null, ShortsViewerSnapshot("viewer", 1, blocked = true))) {
            val detector = ShortsTransitionDetector()
            detector.observe(page(0), 0)
            detector.observe(page(1), 1000)
            assertDecision(TransitionDecision.IGNORE_NOT_SHORTS, detector.observe(interruption, 2000))
            assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(0), 3000))
            // No cross-context identity guarantee: this position can count again.
            assertDecision(TransitionDecision.COUNT, detector.observe(page(1), 4000))
        }
    }

    @Test fun differentViewerEstablishesFreshBaseline() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(20), 0)
        detector.observe(page(21), 1000)
        assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(0, "new"), 2000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(1, "new"), 3000))
    }

    @Test fun missingOrNegativeRowsCannotChangeBaselineOrHistory() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(10), 0)
        detector.observe(page(11), 1000)
        for (row in listOf(null, -1)) {
            assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(row), 2000))
        }
        assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(10), 3000))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(11), 4000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(12), 5000))
    }

    @Test fun debounceDoesNotBackfillSkippedDiscoveriesOnRevisit() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertDecision(TransitionDecision.COUNT, detector.observe(page(1), 1000))
        assertDecision(TransitionDecision.IGNORE_DEBOUNCE, detector.observe(page(2), 1200))
        assertDecision(TransitionDecision.IGNORE_DUPLICATE, detector.observe(page(2), 2000))
        assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(1), 3000))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(2), 4000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(3), 5000))
    }

    @Test fun backwardAndRewatchDoNotMoveLastCountedTime() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        detector.observe(page(1), 1000)
        assertDecision(TransitionDecision.IGNORE_BACKWARD, detector.observe(page(0), 1500))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(1), 1599))
        // Exactly 600 ms after COUNT, not after the ignored observations.
        assertDecision(TransitionDecision.COUNT, detector.observe(page(2), 1600))
    }

    @Test fun rowJumpsCountOnceAndNeverInferMissingVideoCounts() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(5), 0)
        assertDecision(TransitionDecision.COUNT, detector.observe(page(8), 1000))
        detector.observe(page(6), 2000)
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(7), 3000))
        assertDecision(TransitionDecision.IGNORE_REVISITED_POSITION, detector.observe(page(8), 4000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(9), 5000))
    }

    @Test fun twentyRapidRowsKeepExistingDebounceLimitationExplicit() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        val countedRows = (1..20).filter {
            detector.observe(page(it), it * 100L).decision == TransitionDecision.COUNT
        }
        assertEquals(listOf(1, 7, 13, 19), countedRows)
    }

    @Test fun twentySlowForwardRowsAllCount() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertEquals(20, (1..20).count {
            detector.observe(page(it), it * 1000L).decision == TransitionDecision.COUNT
        })
    }

    @Test fun explicitServiceResetClearsOnlyDetectorMemory() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        detector.observe(page(1), 1000)
        detector.reset()
        assertDecision(TransitionDecision.IGNORE_UNKNOWN_DIRECTION, detector.observe(page(0), 2000))
        assertDecision(TransitionDecision.COUNT, detector.observe(page(1), 3000))
    }

    @Test fun directionComparisonDoesNotSubtractOrOverflowIndexes() {
        assertEquals(ScrollDirection.FORWARD, detectScrollDirection(0, Int.MAX_VALUE))
        assertEquals(ScrollDirection.BACKWARD, detectScrollDirection(Int.MAX_VALUE, 0))
    }
}
