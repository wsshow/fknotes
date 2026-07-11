package com.fknotes.app

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

class MainActivity : FlutterFragmentActivity() {
    private companion object {
        const val IMPORT_CHANNEL = "fknotes/attachment_import"
        const val AUDIO_DECODE_CHANNEL = "fknotes/audio_decode"
        const val PICK_REQUEST = 7301
        const val COPY_BUFFER_SIZE = 256 * 1024
        const val PROGRESS_INTERVAL_MS = 80L
        const val THUMBNAIL_WIDTH = 300
        const val THUMBNAIL_DECODE_BOUND = 900
    }

    private val preparationExecutor = Executors.newSingleThreadExecutor()
    private val importExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var importChannel: MethodChannel
    private lateinit var audioDecodeChannel: MethodChannel
    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequest: ImportRequest? = null
    private val importTasks = ConcurrentHashMap<String, ImportTask>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IMPORT_CHANNEL,
        )
        importChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndImport" -> {
                    val type = call.argument<String>("type")
                    val request = type?.let(::requestForType)
                    if (request == null) {
                        result.error("unsupported_attachment", "不支持的附件类型", null)
                    } else {
                        launchPicker(request, result)
                    }
                }
                "importLocalFiles" -> {
                    val type = call.argument<String>("type")
                    val request = type?.let(::requestForType)
                    val files = call.argument<List<Map<String, Any?>>>("files")
                    if (request == null || files == null) {
                        result.error("invalid_import", "附件导入参数无效", null)
                    } else {
                        prepareLocalImports(request, files, result)
                    }
                }
                "cancelImport" -> {
                    val jobId = call.argument<String>("jobId")
                    val task = jobId?.let(importTasks::get)
                    if (task == null) {
                        result.success(false)
                    } else {
                        task.canceled.set(true)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
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
                result.error("invalid_audio", "音频解码参数无效", null)
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
                            error.message ?: "无法解码音频",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun decodeAudioToWav(source: File, destination: File) {
        require(source.exists()) { "音频文件不存在" }
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
            require(trackIndex >= 0 && inputFormat != null) { "文件中没有可识别的音轨" }
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
                            error("设备输出了不支持的 PCM 音频格式")
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

    private fun requestForType(type: String): ImportRequest? = when (type) {
        "image" -> ImportRequest(type, "image/*", "images", true)
        "video" -> ImportRequest(type, "video/*", "video", false)
        "audio" -> ImportRequest(type, "audio/*", "audio", false)
        "document" -> ImportRequest(
            type,
            "*/*",
            "documents",
            false,
            arrayOf(
                "application/pdf",
                "text/plain",
                "text/markdown",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/vnd.ms-powerpoint",
                "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                "application/zip",
            ),
        )
        else -> null
    }

    private fun launchPicker(request: ImportRequest, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("attachment_import_busy", "已有文件选择器正在打开", null)
            return
        }
        pendingResult = result
        pendingRequest = request
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = request.mimeType
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, request.multiple)
            if (request.extraMimeTypes.isNotEmpty()) {
                putExtra(Intent.EXTRA_MIME_TYPES, request.extraMimeTypes)
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, PICK_REQUEST)
        } catch (error: Exception) {
            pendingResult = null
            pendingRequest = null
            result.error("attachment_picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return

        val result = pendingResult ?: return
        val request = pendingRequest ?: return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult = null
            pendingRequest = null
            result.success(null)
            return
        }
        val uris = buildList {
            data.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) add(clip.getItemAt(index).uri)
            }
            if (isEmpty()) data.data?.let(::add)
        }
        if (uris.isEmpty()) {
            pendingResult = null
            pendingRequest = null
            result.success(null)
            return
        }
        preparationExecutor.execute { prepareUriImports(request, uris, result) }
    }

    private fun prepareUriImports(
        request: ImportRequest,
        uris: List<Uri>,
        result: MethodChannel.Result,
    ) {
        try {
            val tasks = uris.map { uri ->
                val metadata = readMetadata(uri, request)
                createTask(request, metadata, sourceUri = uri)
            }
            startPreparedTasks(tasks, result)
        } catch (error: Exception) {
            completePreparationError(result, error)
        }
    }

    private fun prepareLocalImports(
        request: ImportRequest,
        files: List<Map<String, Any?>>,
        result: MethodChannel.Result,
    ) {
        preparationExecutor.execute {
            try {
                val tasks = files.map { item ->
                    val source = File(item["path"] as? String ?: error("缺少文件路径"))
                    require(source.exists()) { "所选文件不存在" }
                    val displayName = (item["name"] as? String)
                        ?.takeIf { it.isNotBlank() }
                        ?: source.name
                    val mimeType = (item["mimeType"] as? String)
                        ?.takeIf { it.isNotBlank() }
                        ?: mimeTypeForName(displayName, request.mimeType)
                    createTask(
                        request,
                        AttachmentMetadata(displayName, source.length(), mimeType),
                        sourceFile = source,
                    )
                }
                startPreparedTasks(tasks, result, clearPicker = false)
            } catch (error: Exception) {
                completePreparationError(result, error, clearPicker = false)
            }
        }
    }

    private fun createTask(
        request: ImportRequest,
        metadata: AttachmentMetadata,
        sourceUri: Uri? = null,
        sourceFile: File? = null,
    ): ImportTask {
        val targetDirectory = File(filesDir, request.folder).apply {
            if (!exists() && !mkdirs()) error("无法创建附件目录")
        }
        val extension = resolveExtension(metadata.displayName, metadata.mimeType, request.type)
        val jobId = UUID.randomUUID().toString()
        return ImportTask(
            id = jobId,
            request = request,
            metadata = metadata,
            sourceUri = sourceUri,
            sourceFile = sourceFile,
            destination = File(targetDirectory, "$jobId.$extension"),
            partialFile = File(targetDirectory, "$jobId.$extension.part"),
        )
    }

    private fun startPreparedTasks(
        tasks: List<ImportTask>,
        result: MethodChannel.Result,
        clearPicker: Boolean = true,
    ) {
        tasks.forEach { importTasks[it.id] = it }
        mainHandler.post {
            if (clearPicker) {
                pendingResult = null
                pendingRequest = null
            }
            result.success(tasks.map(::taskResult))
            tasks.forEach { task -> importExecutor.execute { importAttachment(task) } }
        }
    }

    private fun taskResult(task: ImportTask): Map<String, Any> = mapOf(
        "jobId" to task.id,
        "type" to task.request.type,
        "fileName" to task.metadata.displayName,
        "totalBytes" to task.metadata.totalBytes,
        "mimeType" to task.metadata.mimeType,
    )

    private fun importAttachment(task: ImportTask) {
        var copiedBytes = 0L
        try {
            var lastProgressAt = 0L
            sendProgress(task.id, copiedBytes, task.metadata.totalBytes)
            openInput(task).use { input ->
                FileOutputStream(task.partialFile).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_SIZE)
                    while (true) {
                        if (task.canceled.get()) throw ImportCanceledException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        copiedBytes += count
                        val now = System.currentTimeMillis()
                        if (now - lastProgressAt >= PROGRESS_INTERVAL_MS) {
                            lastProgressAt = now
                            sendProgress(task.id, copiedBytes, task.metadata.totalBytes)
                        }
                    }
                    output.flush()
                }
            }
            if (task.canceled.get()) throw ImportCanceledException()
            if (!task.partialFile.renameTo(task.destination)) error("无法完成附件文件写入")
            val thumbnail = if (task.request.type == "image") {
                createThumbnail(task.destination, task.id)
            } else {
                null
            }
            if (task.canceled.get()) {
                task.destination.delete()
                thumbnail?.delete()
                throw ImportCanceledException()
            }
            val actualBytes = copiedBytes.takeIf { it > 0 } ?: task.destination.length()
            sendProgress(task.id, actualBytes, actualBytes)
            sendEvent(
                "completed",
                buildMap {
                    put("jobId", task.id)
                    put("type", task.request.type)
                    put("filePath", "${task.request.folder}/${task.destination.name}")
                    put("fileName", task.metadata.displayName)
                    put("fileSize", actualBytes)
                    put("mimeType", task.metadata.mimeType)
                    thumbnail?.let { put("thumbnailPath", "thumbnails/${it.name}") }
                },
            )
        } catch (_: ImportCanceledException) {
            task.partialFile.delete()
            task.destination.delete()
            sendEvent("canceled", mapOf("jobId" to task.id))
        } catch (error: Exception) {
            task.partialFile.delete()
            task.destination.delete()
            sendEvent(
                "failed",
                mapOf(
                    "jobId" to task.id,
                    "message" to (error.message ?: "附件导入失败"),
                ),
            )
        } finally {
            importTasks.remove(task.id)
        }
    }

    private fun openInput(task: ImportTask): InputStream = when {
        task.sourceUri != null -> requireNotNull(contentResolver.openInputStream(task.sourceUri)) {
            "无法读取所选文件"
        }
        task.sourceFile != null -> FileInputStream(task.sourceFile)
        else -> error("附件来源无效")
    }

    private fun createThumbnail(image: File, jobId: String): File? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(image.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= THUMBNAIL_DECODE_BOUND) {
            sample *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            image.path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null
        val rotation = ExifInterface(image).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        val degrees = when (rotation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        val oriented = if (degrees == 0f) decoded else Bitmap.createBitmap(
            decoded,
            0,
            0,
            decoded.width,
            decoded.height,
            Matrix().apply { postRotate(degrees) },
            true,
        )
        val scale = minOf(
            1.0,
            THUMBNAIL_WIDTH.toDouble() / maxOf(oriented.width, oriented.height),
        )
        val targetWidth = maxOf(1, (oriented.width * scale).roundToInt())
        val targetHeight = maxOf(1, (oriented.height * scale).roundToInt())
        val thumbnail = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        Canvas(thumbnail).apply {
            drawColor(Color.WHITE)
            drawBitmap(oriented, null, Rect(0, 0, targetWidth, targetHeight), null)
        }
        val directory = File(filesDir, "thumbnails").apply {
            if (!exists() && !mkdirs()) error("无法创建缩略图目录")
        }
        val output = File(directory, "${jobId}_thumb.jpg")
        FileOutputStream(output).use { stream ->
            if (!thumbnail.compress(Bitmap.CompressFormat.JPEG, 86, stream)) {
                error("无法生成缩略图")
            }
        }
        if (oriented !== decoded) oriented.recycle()
        decoded.recycle()
        thumbnail.recycle()
        output
    } catch (_: Exception) {
        null
    }

    private fun readMetadata(uri: Uri, request: ImportRequest): AttachmentMetadata {
        var displayName: String? = null
        var totalBytes = -1L
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) displayName = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) totalBytes = cursor.getLong(sizeIndex)
            }
        }
        val mimeType = contentResolver.getType(uri)?.takeIf { it.isNotBlank() }
            ?: mimeTypeForName(displayName, request.mimeType)
        val extension = resolveExtension(displayName, mimeType, request.type)
        return AttachmentMetadata(
            displayName = displayName?.takeIf { it.isNotBlank() }
                ?: "${request.type}.$extension",
            totalBytes = totalBytes,
            mimeType = mimeType,
        )
    }

    private fun mimeTypeForName(name: String?, fallback: String): String {
        val extension = name?.substringAfterLast('.', "")?.lowercase(Locale.US)
        return extension?.let(MimeTypeMap.getSingleton()::getMimeTypeFromExtension)
            ?: fallback.takeUnless { it == "*/*" }
            ?: "application/octet-stream"
    }

    private fun resolveExtension(displayName: String?, mimeType: String, type: String): String {
        val nameExtension = displayName
            ?.substringAfterLast('.', "")
            ?.lowercase(Locale.US)
            ?.takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
        val mimeExtension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        val fallback = when (type) {
            "image" -> "jpg"
            "video" -> "mp4"
            "audio" -> "m4a"
            else -> "bin"
        }
        return (nameExtension ?: mimeExtension ?: fallback)
            .lowercase(Locale.US)
            .takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
            ?: fallback
    }

    private fun sendProgress(jobId: String, copiedBytes: Long, totalBytes: Long) {
        sendEvent(
            "progress",
            mapOf("jobId" to jobId, "copiedBytes" to copiedBytes, "totalBytes" to totalBytes),
        )
    }

    private fun sendEvent(method: String, arguments: Map<String, Any>) {
        mainHandler.post {
            if (::importChannel.isInitialized) importChannel.invokeMethod(method, arguments)
        }
    }

    private fun completePreparationError(
        result: MethodChannel.Result,
        error: Exception,
        clearPicker: Boolean = true,
    ) {
        mainHandler.post {
            if (clearPicker) {
                pendingResult = null
                pendingRequest = null
            }
            result.error("attachment_import_failed", error.message ?: "附件导入失败", null)
        }
    }

    override fun onDestroy() {
        preparationExecutor.shutdown()
        importExecutor.shutdown()
        super.onDestroy()
    }

    private data class ImportRequest(
        val type: String,
        val mimeType: String,
        val folder: String,
        val multiple: Boolean,
        val extraMimeTypes: Array<String> = emptyArray(),
    )

    private data class AttachmentMetadata(
        val displayName: String,
        val totalBytes: Long,
        val mimeType: String,
    )

    private data class ImportTask(
        val id: String,
        val request: ImportRequest,
        val metadata: AttachmentMetadata,
        val sourceUri: Uri?,
        val sourceFile: File?,
        val destination: File,
        val partialFile: File,
        val canceled: AtomicBoolean = AtomicBoolean(false),
    )

    private class ImportCanceledException : Exception()
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
