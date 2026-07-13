package com.fknotes.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal object DebugDiagnosticsBridge {
    private const val CHANNEL = "fknotes/debug_diagnostics"

    @JvmStatic
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "runtimeInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            runCatching { runtimeInfo(context) }
                .onSuccess(result::success)
                .onFailure {
                    result.error("runtime_info_failed", it.message, null)
                }
        }
    }

    private fun runtimeInfo(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "sdk" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "memoryClassMb" to manager.memoryClass,
            "largeMemoryClassMb" to manager.largeMemoryClass,
            "isLowRamDevice" to manager.isLowRamDevice,
            "availableMemoryBytes" to memory.availMem,
            "totalMemoryBytes" to memory.totalMem,
            "lowMemory" to memory.lowMemory,
            "pageSizeBytes" to runCatching {
                Os.sysconf(OsConstants._SC_PAGESIZE)
            }.getOrNull(),
            "previousExits" to previousExits(context, manager),
        )
    }

    private fun previousExits(
        context: Context,
        manager: ActivityManager,
    ): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return manager.getHistoricalProcessExitReasons(context.packageName, 0, 10).map {
            mapOf(
                "timestamp" to it.timestamp,
                "processName" to it.processName,
                "reason" to exitReason(it.reason),
                "status" to it.status,
                "importance" to it.importance,
                "pssKb" to it.pss,
                "rssKb" to it.rss,
                "description" to it.description,
                "nativeTrace" to readTrace(it),
            )
        }
    }

    private fun readTrace(info: ApplicationExitInfo): String? = runCatching {
        info.traceInputStream?.bufferedReader()?.use { reader ->
            val output = StringBuilder()
            val buffer = CharArray(2048)
            while (output.length < MAX_TRACE_CHARS) {
                val read = reader.read(
                    buffer,
                    0,
                    minOf(buffer.size, MAX_TRACE_CHARS - output.length),
                )
                if (read <= 0) break
                output.append(buffer, 0, read)
            }
            output.toString().takeIf(String::isNotBlank)
        }
    }.getOrNull()

    private fun exitReason(reason: Int): String =
        when (reason) {
            ApplicationExitInfo.REASON_ANR -> "anr"
            ApplicationExitInfo.REASON_CRASH -> "crash"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource_usage"
            ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
            ApplicationExitInfo.REASON_OTHER -> "other"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
            ApplicationExitInfo.REASON_SIGNALED -> "signaled"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
            ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
            else -> "unknown_$reason"
        }

    private const val MAX_TRACE_CHARS = 12_000
}
