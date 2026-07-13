package com.fknotes.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.app.Service
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import com.google.gson.Gson
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

/** Main-process Flutter bridge for the isolated LiteRT-LM worker process. */
internal class LiteRtLmBridge(
    private val context: Context,
    binaryMessenger: BinaryMessenger,
    private val serviceClass: Class<out Service> = LiteRtLmService::class.java,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private data class PendingCommand(
        val message: Message,
        val result: MethodChannel.Result,
    )

    private val methodChannel = MethodChannel(binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(binaryMessenger, EVENT_CHANNEL)
    private val gson = Gson()
    private val pending = ArrayDeque<PendingCommand>()
    private var service: Messenger? = null
    private var binding = false
    private var bound = false
    private var eventSink: EventChannel.EventSink? = null

    private val incoming = Messenger(
        Handler(Looper.getMainLooper()) { message ->
            if (message.what == LiteRtLmIpc.EVENT) {
                emit(
                    requestId = message.data.getInt(LiteRtLmIpc.REQUEST_ID, -1),
                    type = message.data.getString(LiteRtLmIpc.TYPE) ?: "error",
                    data = message.data.getString(LiteRtLmIpc.DATA) ?: "",
                )
                true
            } else {
                false
            }
        },
    )

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            binding = false
            bound = true
            service = Messenger(binder)
            flushPending()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            handleWorkerDeath("LiteRT-LM 推理进程连接已断开")
        }

        override fun onBindingDied(name: ComponentName) {
            handleWorkerDeath("LiteRT-LM 推理进程意外终止")
        }

        override fun onNullBinding(name: ComponentName) {
            handleWorkerDeath("LiteRT-LM 推理服务无法启动")
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val what = when (call.method) {
            "load" -> LiteRtLmIpc.LOAD
            "generate" -> LiteRtLmIpc.GENERATE
            "cancel" -> LiteRtLmIpc.CANCEL
            "unload" -> LiteRtLmIpc.UNLOAD
            else -> {
                result.notImplemented()
                return
            }
        }
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val requestId = (arguments[LiteRtLmIpc.REQUEST_ID] as? Number)?.toInt() ?: -1
        val message = Message.obtain(null, what).apply {
            replyTo = incoming
            data = Bundle().apply {
                putInt(LiteRtLmIpc.REQUEST_ID, requestId)
                putString(LiteRtLmIpc.PAYLOAD, gson.toJson(arguments))
            }
        }
        enqueue(message, result)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pending.forEach { it.result.success(false) }
        pending.clear()
        if (bound) {
            context.unbindService(connection)
            bound = false
        }
        service = null
    }

    private fun enqueue(message: Message, result: MethodChannel.Result) {
        val target = service
        if (target != null) {
            send(target, PendingCommand(message, result))
            return
        }
        pending.add(PendingCommand(message, result))
        if (binding) return
        binding = true
        val started = context.bindService(
            Intent(context, serviceClass),
            connection,
            Context.BIND_AUTO_CREATE,
        )
        if (!started) handleWorkerDeath("LiteRT-LM 推理服务无法启动")
    }

    private fun flushPending() {
        val target = service ?: return
        while (pending.isNotEmpty()) send(target, pending.removeFirst())
    }

    private fun send(target: Messenger, command: PendingCommand) {
        try {
            target.send(command.message)
            command.result.success(true)
        } catch (_: RemoteException) {
            command.result.success(false)
            handleWorkerDeath("LiteRT-LM 推理进程意外终止")
        }
    }

    private fun handleWorkerDeath(reason: String) {
        binding = false
        service = null
        if (bound) {
            try {
                context.unbindService(connection)
            } catch (_: IllegalArgumentException) {
                // The framework may already have removed a dead connection.
            }
        }
        bound = false
        pending.forEach { it.result.success(false) }
        pending.clear()
        emit(-1, "serviceDied", reason)
    }

    private fun emit(requestId: Int, type: String, data: String) {
        eventSink?.success(
            mapOf(
                LiteRtLmIpc.REQUEST_ID to requestId,
                LiteRtLmIpc.TYPE to type,
                LiteRtLmIpc.DATA to data,
            ),
        )
    }

    private companion object {
        const val METHOD_CHANNEL = "fknotes/litert_lm"
        const val EVENT_CHANNEL = "fknotes/litert_lm_events"
    }
}
