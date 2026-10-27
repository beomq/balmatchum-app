package com.beomq.balmatchum

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Foreground reads only, invoked by the existing explicit Flutter refresh. */
internal class HealthConnectStepsReader(private val activity: FlutterFragmentActivity) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val permissions = setOf(HealthPermission.getReadPermission(StepsRecord::class))
    private var pending: MethodChannel.Result? = null
    private val permissionRequest = activity.registerForActivityResult(
        PermissionController.createRequestPermissionResultContract(),
    ) { granted ->
        if (pending != null) {
            if (granted.containsAll(permissions)) {
                read()
            } else {
                finish(DailyStepsObservation.status("permissionDenied"))
            }
        }
    }

    fun request(result: MethodChannel.Result) {
        if (pending != null) {
            result.success(DailyStepsObservation.status("error"))
            return
        }
        pending = result
        scope.launch {
            atBoundary {
                when (HealthConnectClient.getSdkStatus(activity)) {
                    HealthConnectClient.SDK_UNAVAILABLE ->
                        finish(DailyStepsObservation.status("unavailable"))
                    HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                        finish(DailyStepsObservation.status("providerUpdateRequired"))
                    HealthConnectClient.SDK_AVAILABLE -> {
                        val client = HealthConnectClient.getOrCreate(activity)
                        val granted = client.permissionController.getGrantedPermissions()
                        if (granted.containsAll(permissions)) {
                            aggregate(client)
                        } else {
                            permissionRequest.launch(permissions)
                        }
                    }
                    else -> finish(DailyStepsObservation.status("error"))
                }
            }
        }
    }

    private fun read() {
        scope.launch {
            atBoundary { aggregate(HealthConnectClient.getOrCreate(activity)) }
        }
    }

    private suspend fun aggregate(client: HealthConnectClient) {
        val observation = DailyStepsObservation(Instant.now())
        val aggregate = client.aggregate(
            AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(observation.start, observation.end),
            ),
        )
        // No records is unknown, not a measured zero. Aggregate also deduplicates sources.
        finish(observation.result(aggregate[StepsRecord.COUNT_TOTAL]))
    }

    private suspend fun atBoundary(operation: suspend () -> Unit) {
        try {
            operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: SecurityException) {
            finish(DailyStepsObservation.status("permissionDenied"))
        } catch (error: Exception) {
            finish(DailyStepsObservation.status("error"))
        }
    }

    private fun finish(value: Map<String, Any?>) {
        val result = pending
        pending = null
        result?.success(value)
    }

    fun close() {
        finish(DailyStepsObservation.status("error"))
        scope.cancel()
    }
}
