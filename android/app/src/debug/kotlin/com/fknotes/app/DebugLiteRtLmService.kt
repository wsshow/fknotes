package com.fknotes.app

import android.os.Process
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.Date
import kotlin.system.exitProcess

/** Debug-only breadcrumb and uncaught-exception capture for the LLM process. */
class DebugLiteRtLmService : LiteRtLmService() {
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    override fun onCreate() {
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            writeEvent(
                stage = "uncaught_exception",
                requestId = -1,
                error = error,
                thread = thread,
            )
            previousHandler?.uncaughtException(thread, error) ?: exitProcess(10)
        }
        writeEvent(stage = "process_created", requestId = -1)
        super.onCreate()
    }

    override fun onDestroy() {
        writeEvent(stage = "process_destroying", requestId = -1)
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        super.onDestroy()
    }

    override fun onInferenceDiagnostic(
        stage: Int,
        requestId: Int,
        modelBytes: Long,
        backendName: String,
        contextTokens: Int,
        imageInput: Boolean,
        audioInput: Boolean,
        error: Throwable?,
    ) {
        writeEvent(
            stage = STAGES[stage] ?: "stage_$stage",
            requestId = requestId,
            modelBytes = modelBytes,
            backendName = backendName,
            contextTokens = contextTokens,
            imageInput = imageInput,
            audioInput = audioInput,
            error = error,
        )
    }

    private fun writeEvent(
        stage: String,
        requestId: Int,
        modelBytes: Long = 0,
        backendName: String = "",
        contextTokens: Int = 0,
        imageInput: Boolean = false,
        audioInput: Boolean = false,
        error: Throwable? = null,
        thread: Thread = Thread.currentThread(),
    ) {
        runCatching {
            val directory = File(filesDir, "debug_diagnostics").apply { mkdirs() }
            val output = File(directory, "native-worker.jsonl")
            synchronized(FILE_LOCK) {
                if (output.length() > MAX_FILE_BYTES) output.delete()
                val event = JSONObject()
                    .put("timestamp", Date().time)
                    .put("uptimeMs", SystemClock.uptimeMillis())
                    .put("pid", Process.myPid())
                    .put("tid", Process.myTid())
                    .put("thread", thread.name)
                    .put("stage", stage)
                    .put("requestId", requestId)
                if (modelBytes > 0) event.put("modelBytes", modelBytes)
                if (backendName.isNotEmpty()) event.put("backend", backendName)
                if (contextTokens > 0) event.put("contextTokens", contextTokens)
                if (stage == "model_validated") {
                    event.put("imageInput", imageInput)
                    event.put("audioInput", audioInput)
                }
                if (error != null) {
                    event
                        .put("errorType", error.javaClass.name)
                        .put("errorMessage", error.message.orEmpty())
                        .put("stackTrace", Log.getStackTraceString(error).take(MAX_STACK_CHARS))
                }
                output.appendText("$event\n", Charsets.UTF_8)
            }
        }
    }

    private companion object {
        val FILE_LOCK = Any()
        const val MAX_FILE_BYTES = 512L * 1024
        const val MAX_STACK_CHARS = 32_000
        val STAGES = mapOf(
            0 to "service_created",
            1 to "load_received",
            2 to "model_validated",
            3 to "engine_create_started",
            4 to "engine_created",
            5 to "engine_initialize_started",
            6 to "engine_initialized",
            7 to "operation_caught_error",
            8 to "service_destroyed",
            11 to "generation_done_callback",
            12 to "conversation_close_started",
            13 to "conversation_closed",
            14 to "generation_error_callback",
        )
    }
}
