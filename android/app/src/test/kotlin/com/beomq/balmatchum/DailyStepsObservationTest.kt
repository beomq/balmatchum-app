package com.beomq.balmatchum

import java.time.Instant
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DailyStepsObservationTest {
    @Test
    fun rangeUsesSeoulMidnightWhenUtcDayDiffers() {
        // Given an instant just after midnight in Korea, still yesterday in UTC.
        val now = Instant.parse("2026-10-26T15:00:01Z")
        // When today's read window is created.
        val observation = DailyStepsObservation(now)
        // Then the window starts at KST midnight, not UTC midnight.
        assertEquals(Instant.parse("2026-10-26T15:00:00Z"), observation.start)
        assertEquals(now, observation.end)
    }

    @Test
    fun rangeIgnoresDeviceTimeZoneWhenDeviceIsAbroad() {
        // Given a device configured outside Korea.
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
            // When today's read window is created.
            val observation = DailyStepsObservation(Instant.parse("2026-10-27T14:59:59Z"))
            // Then it still begins at Korea's midnight.
            assertEquals(Instant.parse("2026-10-26T15:00:00Z"), observation.start)
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test
    fun missingAggregateIsEmptyWhenNoRecordsExist() {
        // Given an authorized read with no aggregate.
        val observation = DailyStepsObservation(Instant.parse("2026-10-27T01:00:00Z"))
        // When the aggregate is mapped.
        val result = observation.result(null)
        // Then it is not fabricated as a zero-step observation.
        assertEquals("empty", result["status"])
        assertNull(result["dailySteps"])
    }

    @Test
    fun measuredZeroIsAvailableWhenAggregateExists() {
        // Given a real aggregate containing zero.
        val observation = DailyStepsObservation(Instant.parse("2026-10-26T15:00:01.123456789Z"))
        // When the aggregate is mapped.
        val result = observation.result(0)
        // Then the complete shared wire contract retains that measurement.
        assertEquals(
            mapOf(
                "status" to "available",
                "dailySteps" to mapOf(
                    "date" to "2026-10-27",
                    "timeZone" to "Asia/Seoul",
                    "count" to 0L,
                    "observedAt" to "2026-10-26T15:00:01.123456Z",
                ),
            ),
            result,
        )
    }

    @Test
    fun countIsPreservedWhenPositiveAggregateExists() {
        // Given an aggregate read from Health Connect.
        val observation = DailyStepsObservation(Instant.parse("2026-10-27T01:00:00Z"))
        // When a total is mapped.
        val result = observation.result(1234)
        // Then the count is preserved without truncation.
        assertEquals(1234L, (result["dailySteps"] as Map<*, *>)["count"])
    }

    @Test
    fun invalidAggregateIsErrorWhenNegativeCountReturned() {
        // Given a malformed provider total.
        val observation = DailyStepsObservation(Instant.parse("2026-10-27T01:00:00Z"))
        // When it crosses the channel boundary.
        val result = observation.result(-1)
        // Then it never becomes an available observation.
        assertEquals(mapOf("status" to "error", "dailySteps" to null), result)
    }
}
