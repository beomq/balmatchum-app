package com.beomq.balmatchum

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** The server and iPhone contract define a day in Seoul, not the device's zone. */
internal class DailyStepsObservation(val end: Instant) {
    private val day = end.atZone(ZoneId.of("Asia/Seoul")).toLocalDate()
    val start: Instant = day.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant()

    fun result(count: Long?): Map<String, Any?> = when {
        count == null -> status("empty")
        count < 0 -> status("error")
        else -> mapOf(
            "status" to "available",
            "dailySteps" to mapOf(
                "date" to day.toString(),
                "timeZone" to "Asia/Seoul",
                "count" to count,
                // Dart's shared wire validator permits at most six fractional digits.
                "observedAt" to DateTimeFormatter.ISO_INSTANT.format(
                    end.truncatedTo(ChronoUnit.MICROS),
                ),
            ),
        )
    }

    companion object {
        fun status(value: String): Map<String, Any?> =
            mapOf("status" to value, "dailySteps" to null)
    }
}
