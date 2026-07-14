package com.fknotes.app

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.LogSeverity
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.Message as LiteMessage
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns LiteRT-LM in a private Android process. A native inference failure can
 * terminate this worker without taking the Flutter UI or unsaved notes down.
 */
@OptIn(com.google.ai.edge.litertlm.ExperimentalApi::class)
open class LiteRtLmService : Service() {
    private data class Command(
        val requestId: Int,
        val replyTo: Messenger?,
    )

    private val executor = Executors.newSingleThreadExecutor()
    private val controlExecutor = Executors.newSingleThreadExecutor()
    private var engine: Engine? = null
    @Volatile private var conversation: Conversation? = null
    @Volatile private var activeRequestId: Int? = null
    @Volatile private var activeFinished: AtomicBoolean? = null
    private lateinit var messenger: Messenger

    override fun onCreate() {
        super.onCreate()
        messenger = Messenger(
            Handler(Looper.getMainLooper()) { message ->
                when (message.what) {
                    LiteRtLmIpc.LOAD -> execute(message, ::load)
                    LiteRtLmIpc.GENERATE -> execute(message, ::generate)
                    LiteRtLmIpc.CANCEL -> execute(message, ::cancel, controlExecutor)
                    LiteRtLmIpc.UNLOAD -> execute(message, ::unload)
                    else -> return@Handler false
                }
                true
            },
        )
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
        onInferenceDiagnostic(stage = 0)
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        onInferenceDiagnostic(stage = 8)
        runCatching { conversation?.cancelProcess() }
        runCatching { conversation?.close() }
        runCatching { engine?.close() }
        conversation = null
        engine = null
        executor.shutdownNow()
        controlExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun execute(
        message: Message,
        operation: (Command, JSONObject) -> Unit,
        targetExecutor: ExecutorService = executor,
    ) {
        // Handler recycles Message after this callback returns. Snapshot every
        // value needed by the executor and asynchronous inference callbacks.
        val command = Command(
            requestId = message.data.getInt(LiteRtLmIpc.REQUEST_ID, -1),
            replyTo = message.replyTo,
        )
        val payload = message.data.getString(LiteRtLmIpc.PAYLOAD) ?: "{}"
        targetExecutor.execute {
            try {
                operation(command, JSONObject(payload))
            } catch (error: Throwable) {
                onInferenceDiagnostic(
                    stage = 7,
                    requestId = command.requestId,
                    error = error,
                )
                emitError(command, error)
            }
        }
    }

    private fun load(command: Command, payload: JSONObject) {
        val requestId = command.requestId
        onInferenceDiagnostic(stage = 1, requestId = requestId)
        val modelPath = payload.getString("modelPath")
        val model = File(modelPath)
        require(model.isFile && model.length() > 0) { "LiteRT-LM 模型文件不存在或为空" }
        closeRuntime()
        val threads = payload.optInt("threads", 4).coerceIn(1, 8)
        val requestedBackend = payload.optString("backend")
        // Android Emulator exposes a Vulkan stack but no usable render node
        // for LiteRT-LM. GPU initialization can appear successful and then
        // hang forever on the first generation, including cancelProcess().
        val backendName = if (requestedBackend == "gpu" && isEmulator()) {
            "cpu"
        } else {
            requestedBackend
        }
        val backend = backend(backendName, threads)
        // Match Google AI Edge Gallery's LiteRT-LM contract: image and audio
        // pipelines are task-specific, vision uses GPU, and audio uses CPU.
        // A text-only chat must not initialize either multimodal pipeline.
        val visionBackend = if (payload.optBoolean("imageInput")) Backend.GPU() else null
        val audioBackend = if (payload.optBoolean("audioInput")) Backend.CPU(threads) else null
        val contextTokens = payload.optInt("contextTokens", 4096)
        onInferenceDiagnostic(
            stage = 2,
            requestId = requestId,
            modelBytes = model.length(),
            backendName = backendName,
            contextTokens = contextTokens,
            imageInput = payload.optBoolean("imageInput"),
            audioInput = payload.optBoolean("audioInput"),
        )
        onInferenceDiagnostic(stage = 3, requestId = requestId)
        val created = Engine(
            EngineConfig(
                modelPath = model.absolutePath,
                backend = backend,
                visionBackend = visionBackend,
                audioBackend = audioBackend,
                maxNumTokens = contextTokens,
            ),
        )
        onInferenceDiagnostic(stage = 4, requestId = requestId)
        try {
            onInferenceDiagnostic(stage = 5, requestId = requestId)
            created.initialize()
            onInferenceDiagnostic(stage = 6, requestId = requestId)
            engine = created
            emit(command, requestId, "loaded")
        } catch (error: Throwable) {
            runCatching { created.close() }
            throw error
        }
    }

    private fun generate(command: Command, payload: JSONObject) {
        val requestId = command.requestId
        val currentEngine = requireNotNull(engine) { "LiteRT-LM 模型尚未加载" }
        check(activeRequestId == null) { "已有 LiteRT-LM 生成任务正在运行" }
        val messages = payload.getJSONArray("messages")
        require(messages.length() > 0) { "消息不能为空" }
        val lastUserIndex = (messages.length() - 1 downTo 0).firstOrNull { index ->
            messages.getJSONObject(index).optString("role") == "user"
        } ?: error("至少需要一条用户消息")
        require(lastUserIndex == messages.length() - 1) { "最后一条消息必须来自用户" }

        val systemText = buildString {
            for (index in 0 until messages.length()) {
                val item = messages.getJSONObject(index)
                if (item.optString("role") == "system") {
                    if (isNotEmpty()) append("\n\n")
                    append(item.optString("content"))
                }
            }
        }
        val initial = buildList {
            for (index in 0 until lastUserIndex) {
                val item = messages.getJSONObject(index)
                if (item.optString("role") == "system") continue
                add(toMessage(item))
            }
        }
        val sampler = SamplerConfig(
            topK = payload.optInt("topK", 40),
            topP = payload.optDouble("topP", 0.95),
            temperature = payload.optDouble("temperature", 0.7),
        )
        val created = currentEngine.createConversation(
            ConversationConfig(
                systemInstruction = systemText.takeIf(String::isNotBlank)?.let(Contents::of),
                initialMessages = initial,
                samplerConfig = sampler,
                automaticToolCalling = false,
            ),
        )
        conversation = created
        activeRequestId = requestId
        val finished = AtomicBoolean(false)
        activeFinished = finished
        val last = toMessage(messages.getJSONObject(lastUserIndex))
        created.sendMessageAsync(
            last,
            object : MessageCallback {
                override fun onMessage(messageChunk: LiteMessage) {
                    if (!finished.get()) emit(command, requestId, "textDelta", messageChunk.toString())
                }

                override fun onDone() {
                    if (!finished.compareAndSet(false, true)) return
                    onInferenceDiagnostic(stage = 11, requestId = requestId)
                    // LiteRT-LM invokes this callback synchronously from its
                    // native callback thread pool. Closing the conversation
                    // here waits for that same pool to drain and deadlocks the
                    // final callback. Return first, then finalize on our
                    // serialized worker so the next generation cannot overtake
                    // the cleanup.
                    executor.execute {
                        val metrics = runCatching {
                            val benchmark = created.getBenchmarkInfo()
                            JSONObject()
                                .put("promptTokens", benchmark.lastPrefillTokenCount)
                                .put("generatedTokens", benchmark.lastDecodeTokenCount)
                                .put("prefillTokensPerSecond", benchmark.lastPrefillTokensPerSecond)
                                .put("decodeTokensPerSecond", benchmark.lastDecodeTokensPerSecond)
                        }.getOrElse { JSONObject() }
                        onInferenceDiagnostic(stage = 12, requestId = requestId)
                        finishConversation(created, requestId)
                        onInferenceDiagnostic(stage = 13, requestId = requestId)
                        emit(command, requestId, "completed", metrics.toString())
                    }
                }

                override fun onError(throwable: Throwable) {
                    if (!finished.compareAndSet(false, true)) return
                    onInferenceDiagnostic(stage = 14, requestId = requestId, error = throwable)
                    // See onDone(): native owns the current callback thread, so
                    // conversation teardown must happen after this returns.
                    executor.execute {
                        finishConversation(created, requestId)
                        emitError(command, throwable, requestId)
                    }
                }
            },
        )
    }

    private fun cancel(command: Command, payload: JSONObject) {
        val requestId = command.requestId
        val current = conversation
        val finished = activeFinished
        if (current == null || activeRequestId != requestId || finished == null) {
            emit(command, requestId, "canceled")
            return
        }
        if (!finished.compareAndSet(false, true)) return
        try {
            current.cancelProcess()
        } catch (error: Throwable) {
            finishConversation(current, requestId)
            emitError(command, error, requestId)
            return
        }
        finishConversation(current, requestId)
        emit(command, requestId, "canceled")
    }

    private fun unload(command: Command, payload: JSONObject) {
        val requestId = command.requestId
        closeRuntime()
        emit(command, requestId, "unloaded")
    }

    private fun toMessage(item: JSONObject): LiteMessage {
        val contents = mutableListOf<Content>()
        val attachments = item.optJSONArray("attachments") ?: JSONArray()
        for (index in 0 until attachments.length()) {
            val attachment = attachments.getJSONObject(index)
            val path = File(attachment.getString("path")).absoluteFile
            require(path.isFile) { "多模态附件不存在：${path.name}" }
            when {
                attachment.optString("mimeType").startsWith("image/") ->
                    contents.add(Content.ImageFile(path.path))
                attachment.optString("mimeType").startsWith("audio/") ->
                    contents.add(Content.AudioFile(path.path))
                else -> error("不支持的多模态附件")
            }
        }
        item.optString("content").takeIf(String::isNotEmpty)?.let {
            contents.add(Content.Text(it))
        }
        require(contents.isNotEmpty()) { "消息内容不能为空" }
        val value = Contents.of(contents)
        return when (item.optString("role")) {
            "user" -> LiteMessage.user(value)
            "assistant" -> LiteMessage.model(value)
            "tool" -> LiteMessage.tool(value)
            else -> error("不支持的消息角色")
        }
    }

    private fun backend(name: String, threads: Int): Backend =
        if (name == "gpu") Backend.GPU() else Backend.CPU(threadCount = threads.coerceIn(1, 8))

    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.startsWith("generic") ||
            Build.MODEL.startsWith("sdk_gphone") ||
            Build.HARDWARE.contains("ranchu") ||
            Build.HARDWARE.contains("goldfish")

    @Synchronized
    private fun finishConversation(target: Conversation, requestId: Int) {
        if (conversation !== target || activeRequestId != requestId) return
        try {
            runCatching { target.close() }
        } finally {
            conversation = null
            activeRequestId = null
            activeFinished = null
        }
    }

    @Synchronized
    private fun closeRuntime() {
        conversation?.let {
            runCatching { it.cancelProcess() }
            runCatching { it.close() }
        }
        conversation = null
        activeRequestId = null
        activeFinished = null
        runCatching { engine?.close() }
        engine = null
    }

    private fun emit(command: Command, requestId: Int, type: String, data: String = "") {
        val response = Message.obtain(null, LiteRtLmIpc.EVENT).apply {
            this.data = android.os.Bundle().apply {
                putInt(LiteRtLmIpc.REQUEST_ID, requestId)
                putString(LiteRtLmIpc.TYPE, type)
                putString(LiteRtLmIpc.DATA, data)
            }
        }
        try {
            command.replyTo?.send(response)
        } catch (_: Throwable) {
            // The UI process may have gone away; the worker can be reclaimed.
        }
    }

    private fun emitError(command: Command, error: Throwable, requestId: Int = command.requestId) {
        val detail = error.message?.takeIf(String::isNotBlank) ?: error.javaClass.simpleName
        emit(command, requestId, "error", detail)
    }

    /** Debug builds override this without placing diagnostic writers in Release. */
    protected open fun onInferenceDiagnostic(
        stage: Int,
        requestId: Int = -1,
        modelBytes: Long = 0,
        backendName: String = "",
        contextTokens: Int = 0,
        imageInput: Boolean = false,
        audioInput: Boolean = false,
        error: Throwable? = null,
    ) = Unit
}
