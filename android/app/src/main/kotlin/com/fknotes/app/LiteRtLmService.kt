package com.fknotes.app

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
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
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns LiteRT-LM in a private Android process. A native inference failure can
 * terminate this worker without taking the Flutter UI or unsaved notes down.
 */
@OptIn(com.google.ai.edge.litertlm.ExperimentalApi::class)
class LiteRtLmService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private var engine: Engine? = null
    @Volatile private var conversation: Conversation? = null
    @Volatile private var activeRequestId: Int? = null
    @Volatile private var activeFinished: AtomicBoolean? = null

    private val messenger = Messenger(
        Handler(mainLooper) { message ->
            when (message.what) {
                LiteRtLmIpc.LOAD -> execute(message, ::load)
                LiteRtLmIpc.GENERATE -> execute(message, ::generate)
                LiteRtLmIpc.CANCEL -> execute(message, ::cancel)
                LiteRtLmIpc.UNLOAD -> execute(message, ::unload)
                else -> return@Handler false
            }
            true
        },
    )

    override fun onCreate() {
        super.onCreate()
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
    }

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        runCatching { conversation?.cancelProcess() }
        runCatching { conversation?.close() }
        runCatching { engine?.close() }
        conversation = null
        engine = null
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun execute(message: Message, operation: (Message, JSONObject) -> Unit) {
        val payload = message.data.getString(LiteRtLmIpc.PAYLOAD) ?: "{}"
        executor.execute {
            try {
                operation(message, JSONObject(payload))
            } catch (error: Throwable) {
                emitError(message, error)
            }
        }
    }

    private fun load(message: Message, payload: JSONObject) {
        val requestId = requestId(message)
        val modelPath = payload.getString("modelPath")
        val model = File(modelPath)
        require(model.isFile && model.length() > 0) { "LiteRT-LM 模型文件不存在或为空" }
        closeRuntime()
        val threads = payload.optInt("threads", 4).coerceIn(1, 8)
        val backend = backend(payload.optString("backend"), threads)
        // Match Google AI Edge Gallery's LiteRT-LM contract: image and audio
        // pipelines are task-specific, vision uses GPU, and audio uses CPU.
        // A text-only chat must not initialize either multimodal pipeline.
        val visionBackend = if (payload.optBoolean("imageInput")) Backend.GPU() else null
        val audioBackend = if (payload.optBoolean("audioInput")) Backend.CPU(threads) else null
        val created = Engine(
            EngineConfig(
                modelPath = model.absolutePath,
                backend = backend,
                visionBackend = visionBackend,
                audioBackend = audioBackend,
                maxNumTokens = payload.optInt("contextTokens", 4096),
            ),
        )
        try {
            created.initialize()
            engine = created
            emit(message, requestId, "loaded")
        } catch (error: Throwable) {
            runCatching { created.close() }
            throw error
        }
    }

    private fun generate(message: Message, payload: JSONObject) {
        val requestId = requestId(message)
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
                    if (!finished.get()) emit(message, requestId, "textDelta", messageChunk.toString())
                }

                override fun onDone() {
                    if (!finished.compareAndSet(false, true)) return
                    val metrics = runCatching {
                        val benchmark = created.getBenchmarkInfo()
                        JSONObject()
                            .put("promptTokens", benchmark.lastPrefillTokenCount)
                            .put("generatedTokens", benchmark.lastDecodeTokenCount)
                            .put("prefillTokensPerSecond", benchmark.lastPrefillTokensPerSecond)
                            .put("decodeTokensPerSecond", benchmark.lastDecodeTokensPerSecond)
                    }.getOrElse { JSONObject() }
                    finishConversation(created, requestId)
                    emit(message, requestId, "completed", metrics.toString())
                }

                override fun onError(throwable: Throwable) {
                    if (!finished.compareAndSet(false, true)) return
                    finishConversation(created, requestId)
                    emitError(message, throwable, requestId)
                }
            },
        )
    }

    private fun cancel(message: Message, payload: JSONObject) {
        val requestId = requestId(message)
        val current = conversation
        val finished = activeFinished
        if (current == null || activeRequestId != requestId || finished == null) {
            emit(message, requestId, "canceled")
            return
        }
        if (!finished.compareAndSet(false, true)) return
        try {
            current.cancelProcess()
        } catch (error: Throwable) {
            finishConversation(current, requestId)
            emitError(message, error, requestId)
            return
        }
        finishConversation(current, requestId)
        emit(message, requestId, "canceled")
    }

    private fun unload(message: Message, payload: JSONObject) {
        val requestId = requestId(message)
        closeRuntime()
        emit(message, requestId, "unloaded")
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

    private fun requestId(message: Message): Int =
        message.data.getInt(LiteRtLmIpc.REQUEST_ID, -1)

    private fun emit(message: Message, requestId: Int, type: String, data: String = "") {
        val response = Message.obtain(null, LiteRtLmIpc.EVENT).apply {
            this.data = android.os.Bundle().apply {
                putInt(LiteRtLmIpc.REQUEST_ID, requestId)
                putString(LiteRtLmIpc.TYPE, type)
                putString(LiteRtLmIpc.DATA, data)
            }
        }
        try {
            message.replyTo?.send(response)
        } catch (_: Throwable) {
            // The UI process may have gone away; the worker can be reclaimed.
        }
    }

    private fun emitError(message: Message, error: Throwable, requestId: Int = requestId(message)) {
        val detail = error.message?.takeIf(String::isNotBlank) ?: error.javaClass.simpleName
        emit(message, requestId, "error", detail)
    }
}
