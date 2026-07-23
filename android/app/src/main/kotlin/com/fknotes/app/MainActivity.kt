package com.fknotes.app

import android.app.Activity
import android.app.Service
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.LocaleList
import android.app.LocaleManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.util.concurrent.Executors

open class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val AUDIO_DECODE_CHANNEL = "fknotes/audio_decode"
        const val APP_LOCALE_CHANNEL = "fknotes/app_locale"
        const val BACKUP_EXPORT_CHANNEL = "fknotes/backup_export"
        const val BACKUP_SAVE_REQUEST = 7302
        const val COPY_BUFFER_SIZE = 256 * 1024
    }

    private val preparationExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var audioDecodeChannel: MethodChannel
    private lateinit var appLocaleChannel: MethodChannel
    private lateinit var backupExportChannel: MethodChannel
    private var liteRtLmBridge: LiteRtLmBridge? = null
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liteRtLmBridge = LiteRtLmBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            liteRtLmServiceClass(),
        )
        audioDecodeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_DECODE_CHANNEL,
        )
        audioDecodeChannel.setMethodCallHandler { call, result ->
            if (call.method != "decodeToWav") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            val outputPath = call.argument<String>("outputPath")
            if (sourcePath == null || outputPath == null) {
                result.error(
                    "invalid_audio",
                    getString(R.string.invalid_audio_decode),
                    null,
                )
                return@setMethodCallHandler
            }
            preparationExecutor.execute {
                try {
                    decodeAudioToWav(File(sourcePath), File(outputPath))
                    mainHandler.post { result.success(outputPath) }
                } catch (error: Exception) {
                    File(outputPath).delete()
                    mainHandler.post {
                        result.error(
                            "audio_decode_failed",
                            error.message ?: getString(R.string.audio_decode_failed),
                            null,
                        )
                    }
                }
            }
        }
        appLocaleChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LOCALE_CHANNEL,
        )
        appLocaleChannel.setMethodCallHandler { call, result ->
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                result.success(null)
                return@setMethodCallHandler
            }
            val localeManager = getSystemService(LocaleManager::class.java)
            when (call.method) {
                "getApplicationLocale" ->
                    result.success(localeManager.applicationLocales.toLanguageTags())
                "setApplicationLocale" -> {
                    val languageTag = call.arguments as? String ?: ""
                    localeManager.applicationLocales = LocaleList.forLanguageTags(languageTag)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        backupExportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_EXPORT_CHANNEL,
        )
        backupExportChannel.setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            val suggestedName = call.argument<String>("suggestedName")
            val mimeType = call.argument<String>("mimeType") ?: "application/zip"
            if (sourcePath.isNullOrBlank() || suggestedName.isNullOrBlank()) {
                result.error("invalid_backup_export", "Missing backup file information", null)
                return@setMethodCallHandler
            }
            launchBackupExporter(File(sourcePath), suggestedName, mimeType, result)
        }
    }

    protected open fun liteRtLmServiceClass(): Class<out Service> =
        LiteRtLmService::class.java

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (::backupExportChannel.isInitialized) {
            backupExportChannel.setMethodCallHandler(null)
        }
        liteRtLmBridge?.dispose()
        liteRtLmBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun decodeAudioToWav(source: File, destination: File) {
        require(source.exists()) { getString(R.string.audio_file_missing) }
        destination.parentFile?.mkdirs()
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var writer: Pcm16WavWriter? = null
        try {
            extractor.setDataSource(source.path)
            var trackIndex = -1
            var inputFormat: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(index)
                val mime = candidate.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("audio/")) {
                    trackIndex = index
                    inputFormat = candidate
                    break
                }
            }
            require(trackIndex >= 0 && inputFormat != null) {
                getString(R.string.audio_track_missing)
            }
            extractor.selectTrack(trackIndex)
            val format = requireNotNull(inputFormat)
            val mime = requireNotNull(format.getString(MediaFormat.KEY_MIME))
            if (android.os.Build.VERSION.SDK_INT >= 24) {
                format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            }
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            writer = Pcm16WavWriter(destination, 16_000)
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var resampleAccumulator = 0L
            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = decoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = requireNotNull(decoder.getInputBuffer(inputIndex))
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            decoder.queueInputBuffer(
                                inputIndex,
                                0,
                                size,
                                extractor.sampleTime,
                                0,
                            )
                            extractor.advance()
                        }
                    }
                }

                when (val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outputFormat = decoder.outputFormat
                        sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (android.os.Build.VERSION.SDK_INT >= 24 &&
                            outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) != AudioFormat.ENCODING_PCM_16BIT
                        ) {
                            error(getString(R.string.unsupported_pcm_format))
                        }
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (outputIndex >= 0) {
                        if (info.size > 0) {
                            val output = requireNotNull(decoder.getOutputBuffer(outputIndex))
                            output.order(ByteOrder.LITTLE_ENDIAN)
                            output.position(info.offset)
                            output.limit(info.offset + info.size)
                            val frameCount = (info.size / 2) / channelCount
                            repeat(frameCount) {
                                var mixed = 0
                                repeat(channelCount) { mixed += output.short.toInt() }
                                val mono = (mixed / channelCount).coerceIn(-32768, 32767).toShort()
                                resampleAccumulator += 16_000L
                                while (resampleAccumulator >= sampleRate) {
                                    writer.write(mono)
                                    resampleAccumulator -= sampleRate.toLong()
                                }
                            }
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        decoder.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
            writer.finish()
            writer = null
        } finally {
            writer?.close()
            try {
                decoder?.stop()
            } catch (_: Exception) {
                // Decoder may fail before start; release is still required.
            }
            decoder?.release()
            extractor.release()
        }
    }

    private fun launchBackupExporter(
        source: File,
        suggestedName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        if (!source.isFile) {
            result.error("backup_file_missing", "The backup file no longer exists", null)
            return
        }
        if (pendingBackupResult != null) {
            result.error("backup_export_busy", "Another system file picker is active", null)
            return
        }
        pendingBackupResult = result
        pendingBackupSource = source
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, BACKUP_SAVE_REQUEST)
        } catch (error: Exception) {
            pendingBackupResult = null
            pendingBackupSource = null
            result.error("backup_export_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == BACKUP_SAVE_REQUEST) {
            completeBackupExport(resultCode, data)
        }
    }

    private fun completeBackupExport(resultCode: Int, data: Intent?) {
        val result = pendingBackupResult ?: return
        val source = pendingBackupSource
        pendingBackupResult = null
        pendingBackupSource = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(false)
            return
        }
        if (source == null || !source.isFile) {
            result.error("backup_file_missing", "The backup file no longer exists", null)
            return
        }
        val destination = requireNotNull(data.data)
        preparationExecutor.execute {
            try {
                FileInputStream(source).use { input ->
                    val output = contentResolver.openOutputStream(destination, "w")
                        ?: throw IOException("Unable to open the selected destination")
                    output.use {
                        input.copyTo(it, COPY_BUFFER_SIZE)
                        it.flush()
                    }
                }
                mainHandler.post { result.success(true) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("backup_export_failed", error.message, null)
                }
            }
        }
    }

    override fun onDestroy() {
        preparationExecutor.shutdown()
        super.onDestroy()
    }
}

private class Pcm16WavWriter(
    file: File,
    private val sampleRate: Int,
) {
    private val output = RandomAccessFile(file, "rw")
    private val buffer = ByteArray(16 * 1024)
    private var buffered = 0
    private var sampleCount = 0L

    init {
        output.setLength(0)
        output.write(ByteArray(44))
    }

    fun write(sample: Short) {
        if (buffered + 2 > buffer.size) flushBuffer()
        val value = sample.toInt()
        buffer[buffered++] = (value and 0xff).toByte()
        buffer[buffered++] = (value ushr 8 and 0xff).toByte()
        sampleCount++
    }

    fun finish() {
        flushBuffer()
        val dataSize = sampleCount * 2
        output.seek(0)
        output.write(wavHeader(dataSize))
        output.fd.sync()
        output.close()
    }

    fun close() {
        try {
            output.close()
        } catch (_: Exception) {
            // Already closed by finish().
        }
    }

    private fun flushBuffer() {
        if (buffered == 0) return
        output.write(buffer, 0, buffered)
        buffered = 0
    }

    private fun wavHeader(dataSize: Long): ByteArray {
        val header = ByteArray(44)
        fun ascii(offset: Int, value: String) {
            value.toByteArray(Charsets.US_ASCII).copyInto(header, offset)
        }
        fun little16(offset: Int, value: Int) {
            header[offset] = (value and 0xff).toByte()
            header[offset + 1] = (value ushr 8 and 0xff).toByte()
        }
        fun little32(offset: Int, value: Long) {
            repeat(4) { index ->
                header[offset + index] = (value ushr (8 * index) and 0xff).toByte()
            }
        }
        ascii(0, "RIFF")
        little32(4, 36 + dataSize)
        ascii(8, "WAVE")
        ascii(12, "fmt ")
        little32(16, 16)
        little16(20, 1)
        little16(22, 1)
        little32(24, sampleRate.toLong())
        little32(28, (sampleRate * 2).toLong())
        little16(32, 2)
        little16(34, 16)
        ascii(36, "data")
        little32(40, dataSize)
        return header
    }
}
