package com.example.doom_meter.tracking

import org.junit.Assert.*
import org.junit.Test

class ShortsTransitionDetectorTest {
    private fun page(row: Int?, session: String = "viewer") = ShortsViewerSnapshot(session, row)

    @Test fun entryAndRepeatedEventsNeverCount() {
        val detector = ShortsTransitionDetector()
        assertNull(detector.observe(null, 0))
        assertNull(detector.observe(page(11), 100))
        for (time in listOf(200L, 500L, 900L, 5000L)) {
            assertNull(detector.observe(page(11), time))
        }
    }

    @Test fun countsForwardAndBackwardRowsOnce() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(11), 0)
        assertEquals("next", detector.observe(page(12), 1000)?.direction)
        assertNull(detector.observe(page(12), 1200))
        assertEquals("next", detector.observe(page(13), 2000)?.direction)
        assertEquals("previous", detector.observe(page(12), 3000)?.direction)
    }

    @Test fun animationWithoutASettledPagePreservesBaseline() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertNull(detector.observe(page(null), 500))
        assertEquals(ShortsTransition(0, 1), detector.observe(page(1), 1000))
    }

    @Test fun commentsExitAndNewViewerEstablishNewBaselines() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertNull(detector.observe(ShortsViewerSnapshot("viewer", 1, blocked = true), 1000))
        assertNull(detector.observe(page(1), 2000))
        assertNull(detector.observe(null, 2500))
        assertNull(detector.observe(page(5), 3000))
        assertNull(detector.observe(page(20, "another-viewer"), 4000))
        assertEquals(ShortsTransition(20, 21), detector.observe(page(21, "another-viewer"), 5000))
    }

    @Test fun debounceSuppressesRapidChangesWithoutAccumulatingSkippedRows() {
        val detector = ShortsTransitionDetector()
        detector.observe(page(0), 0)
        assertNotNull(detector.observe(page(1), 1000))
        assertNull(detector.observe(page(2), 1200))
        assertEquals(ShortsTransition(2, 3), detector.observe(page(3), 1800))
    }
}
