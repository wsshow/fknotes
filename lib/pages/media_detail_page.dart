import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/note_service.dart';
import '../services/ocr_service.dart';
import '../services/speech_model_service.dart';
import '../services/speech_transcription_service.dart';
import '../services/speaker_diarization_model_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/fk_markdown_view.dart';
import 'note_editor_page.dart';
import 'model_management_page.dart';
import 'transcript_editor_page.dart';

class MediaDetailPage extends StatefulWidget {
  final NoteEntry entry;
  final NoteAttachment? attachment;
  const MediaDetailPage({super.key, required this.entry, this.attachment});

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  final _storage = FileStorageService.instance;
  late NoteEntry _entry;
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  bool _recognizing = false;
  final _speech = SpeechTranscriptionService.instance;
  final _speechModels = SpeechModelService.instance;
  final _speakerModels = SpeakerDiarizationModelService.instance;
  SpeechModelInfo? _speechModel;
  SpeakerDiarizationModelInfo? _speakerModel;
  double? _modelImportProgress;
  bool _importingModel = false;
  bool _cancelModelDownload = false;
  String _modelOperationLabel = '正在准备模型';
  int _modelTransferredBytes = 0;
  int _modelTotalBytes = 0;
  double _modelBytesPerSecond = 0;
  DateTime? _modelSpeedSampleAt;
  int _modelSpeedSampleBytes = 0;
  bool _modelVerifying = false;
  bool _downloadingModelOnline = false;
  String? _handledTranscriptionKey;

  NoteEntry get entry => _entry;
  NoteAttachment? get attachment {
    final requested = widget.attachment;
    if (requested == null) return entry.primaryAttachment;
    for (final item in entry.allAttachments) {
      if (item.filePath == requested.filePath) return item;
    }
    return requested;
  }

  File? get _file {
    final path = attachment?.filePath;
    if (path == null) return null;
    final file = File(_storage.absolutePath(path));
    return file.existsSync() ? file : null;
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _speech.addListener(_speechChanged);
    _initMedia();
    _loadSpeechModel();
  }

  Future<void> _loadSpeechModel() async {
    final results = await Future.wait<Object>([
      _speechModels.inspect(),
      _speakerModels.inspect(),
    ]);
    if (mounted) {
      setState(() {
        _speechModel = results[0] as SpeechModelInfo;
        _speakerModel = results[1] as SpeakerDiarizationModelInfo;
      });
    }
  }

  void _speechChanged() {
    if (!mounted) return;
    final job = _speech.jobFor(attachment?.filePath ?? '');
    setState(() {});
    if (job?.status == TranscriptionStatus.completed &&
        _handledTranscriptionKey != job!.key) {
      _handledTranscriptionKey = job.key;
      _refreshEntry();
    }
  }

  Future<void> _refreshEntry() async {
    final id = entry.id;
    if (id == null) return;
    final refreshed = await NoteService.instance.getEntry(id);
    if (refreshed != null && mounted) setState(() => _entry = refreshed);
  }

  Future<void> _initMedia() async {
    final file = _file;
    if (file == null) return;
    if (attachment?.type == NoteType.video) {
      _video = VideoPlayerController.file(file);
      await _video!.initialize();
      _video!.addListener(_mediaChanged);
    } else if (attachment?.type == NoteType.audio) {
      _audio = AudioPlayer();
      await _audio!.setFilePath(file.path);
      _audio!.positionStream.listen((position) {
        if (mounted) setState(() => _audioPosition = position);
      });
      _audio!.durationStream.listen((duration) {
        if (duration != null && mounted) {
          setState(() => _audioDuration = duration);
        }
      });
    }
    if (mounted) setState(() {});
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
    if (!mounted || entry.id == null) return;
    final refreshed = await NoteService.instance.getEntry(entry.id!);
    if (refreshed != null && mounted) setState(() => _entry = refreshed);
  }

  Future<void> _openExternal() async {
    final file = _file;
    if (file == null) return;
    final result = await OpenFile.open(file.path);
    if (!mounted || result.type == ResultType.done) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _copyOcr() async {
    await Clipboard.setData(ClipboardData(text: attachment?.ocrText ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('识别文字已复制')));
    }
  }

  Future<void> _recognizeText() async {
    final file = _file;
    if (file == null || attachment?.type != NoteType.image || _recognizing) {
      return;
    }
    setState(() => _recognizing = true);
    final result = await OcrService.instance.recognizeText(file.path);
    if (!mounted) return;
    if (!result.hasText) {
      setState(() => _recognizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.didFail ? 'OCR 识别失败：${result.errorMessage}' : '未识别到清晰文字',
          ),
        ),
      );
      return;
    }
    final activePath = attachment!.filePath;
    final updated = entry.copyWith(
      attachments: [
        for (final item in entry.allAttachments)
          item.filePath == activePath
              ? item.copyWith(ocrText: result.text)
              : item,
      ],
      updatedAt: DateTime.now(),
    );
    await context.read<NoteProvider>().updateEntry(updated);
    if (mounted) {
      setState(() {
        _entry = updated;
        _recognizing = false;
      });
    }
  }

  Future<void> _importSpeechModel() async {
    if (_importingModel) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入离线识别模型'),
        content: const Text(
          '请从解压后的 SenseVoice Small INT8 模型目录中，同时选择 ONNX 模型和 tokens.txt。\n\n'
          '模型约 228 MB，只保存在本机，不会进入笔记备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() {
      _importingModel = true;
      _modelImportProgress = 0;
      _modelOperationLabel = '正在导入离线模型';
      _downloadingModelOnline = false;
      _resetModelTransferStats();
    });
    try {
      final info = await _speechModels.pickAndImport(
        onProgress: (progress) {
          if (mounted) _updateModelTransfer(progress);
        },
      );
      if (info != null && mounted) {
        setState(() => _speechModel = info);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线语音识别模型已导入')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('模型导入失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingModel = false;
          _modelImportProgress = null;
        });
      }
    }
  }

  Future<void> _downloadSpeechModel() async {
    if (_importingModel) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载离线识别模型？'),
        content: const Text(
          '将从 ModelScope 魔搭社区下载约 228 MB，建议使用 Wi-Fi。\n\n'
          '下载是应用唯一需要联网的功能；笔记和音频不会上传。中断后可继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() {
      _importingModel = true;
      _cancelModelDownload = false;
      _modelImportProgress = 0;
      _modelOperationLabel = '正在从 ModelScope 下载';
      _downloadingModelOnline = true;
      _resetModelTransferStats();
    });
    try {
      final info = await _speechModels.downloadFromModelScope(
        shouldCancel: () => _cancelModelDownload,
        onProgress: (progress) {
          if (mounted) _updateModelTransfer(progress);
        },
      );
      if (mounted) {
        setState(() => _speechModel = info);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('离线语音识别模型下载完成')));
      }
    } on SpeechModelDownloadCanceled {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已暂停下载，下次会从断点继续')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('模型下载失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingModel = false;
          _modelImportProgress = null;
        });
      }
    }
  }

  void _resetModelTransferStats() {
    _modelTransferredBytes = 0;
    _modelTotalBytes = 0;
    _modelBytesPerSecond = 0;
    _modelSpeedSampleAt = null;
    _modelSpeedSampleBytes = 0;
    _modelVerifying = false;
  }

  void _updateModelTransfer(SpeechModelImportProgress progress) {
    final now = DateTime.now();
    final previousAt = _modelSpeedSampleAt;
    if (!progress.verifying && previousAt != null) {
      final elapsed = now.difference(previousAt).inMilliseconds;
      final transferred = progress.copiedBytes - _modelSpeedSampleBytes;
      if (elapsed >= 350 && transferred >= 0) {
        final instant = transferred * 1000 / elapsed;
        _modelBytesPerSecond = _modelBytesPerSecond == 0
            ? instant
            : _modelBytesPerSecond * .65 + instant * .35;
        _modelSpeedSampleAt = now;
        _modelSpeedSampleBytes = progress.copiedBytes;
      }
    } else if (previousAt == null) {
      _modelSpeedSampleAt = now;
      _modelSpeedSampleBytes = progress.copiedBytes;
    }
    setState(() {
      _modelImportProgress = progress.fraction;
      _modelTransferredBytes = progress.copiedBytes;
      _modelTotalBytes = progress.totalBytes;
      _modelVerifying = progress.verifying;
      if (progress.verifying) _modelOperationLabel = '正在完成安装';
    });
  }

  String _modelTransferDescription() {
    final transferred = _formatSize(_modelTransferredBytes);
    final total = _formatSize(_modelTotalBytes);
    final verb = _downloadingModelOnline ? '已下载' : '已导入';
    if (_modelVerifying) return '$verb $transferred · 正在完成安装';
    final speed = _modelBytesPerSecond <= 0
        ? '正在测速…'
        : '${_formatSize(_modelBytesPerSecond.round())}/s';
    return '$verb $transferred / $total · $speed';
  }

  Future<void> _removeSpeechModel() async {
    if (_speech.jobs.any((job) => job.isRunning)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先等待正在进行的转写结束')));
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除离线模型？'),
        content: const Text('将释放约 228 MB 空间。已经保存的转写文字不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除模型'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await _speechModels.remove();
    if (mounted) {
      setState(() => _speechModel = const SpeechModelInfo(installed: false));
    }
  }

  Future<void> _startTranscription() async {
    final item = attachment;
    final noteId = entry.id;
    if (item == null || noteId == null) return;
    if (_speechModel?.installed != true) {
      await _importSpeechModel();
      if (_speechModel?.installed != true) return;
    }
    await _audio?.pause();
    await _speech.start(noteId: noteId, attachment: item);
  }

  Future<void> _startSpeakerTranscription() async {
    final item = attachment;
    final noteId = entry.id;
    if (item == null || noteId == null) return;
    if (_speechModel?.installed != true) {
      await _importSpeechModel();
      if (_speechModel?.installed != true) return;
    }
    var speakerModel = await _speakerModels.inspect();
    if (!speakerModel.installed) {
      if (!mounted) return;
      final manage = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要说话人分离模型'),
          content: const Text(
            '首次使用需在本地模型中下载约 44.4 MB。'
            '模型安装后，分段和转写都完全在设备上完成。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('管理模型'),
            ),
          ],
        ),
      );
      if (manage == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ModelManagementPage(
              focusModelId: SpeakerDiarizationModelService.modelId,
            ),
          ),
        );
        speakerModel = await _speakerModels.inspect();
        if (mounted) setState(() => _speakerModel = speakerModel);
      }
      if (!speakerModel.installed) return;
    }
    if (!mounted) return;
    final speakerCount = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('说话人数量'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              '当前支持最长 30 分钟的录音；人数越准确，分离结果通常越稳定。',
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, -1),
            child: const ListTile(
              leading: Icon(Icons.auto_awesome_rounded),
              title: Text('自动估算'),
              subtitle: Text('适合不确定人数的录音'),
            ),
          ),
          for (var count = 2; count <= 8; count++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, count),
              child: Text('$count 位说话人'),
            ),
        ],
      ),
    );
    if (speakerCount == null) return;
    await _audio?.pause();
    await _speech.start(
      noteId: noteId,
      attachment: item,
      speakerCount: speakerCount,
    );
  }

  Future<void> _openModelManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const ModelManagementPage(focusModelId: SpeechModelService.modelId),
      ),
    );
    if (mounted) await _loadSpeechModel();
  }

  Future<void> _copyTranscript() async {
    final text = attachment?.transcript?.trim() ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('转写文字已复制')));
    }
  }

  Future<void> _editTranscript() async {
    final item = attachment;
    if (item == null) return;
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            TranscriptEditorPage(initialText: item.transcript ?? ''),
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    final activePath = item.filePath;
    final updated = entry.copyWith(
      attachments: [
        for (final attachment in entry.allAttachments)
          attachment.filePath == activePath
              ? attachment.copyWith(
                  transcript: value,
                  transcribedAt: DateTime.now(),
                )
              : attachment,
      ],
      updatedAt: DateTime.now(),
    );
    await context.read<NoteProvider>().updateEntry(updated);
    if (mounted) setState(() => _entry = updated);
  }

  @override
  void dispose() {
    _video?.removeListener(_mediaChanged);
    _video?.dispose();
    _audio?.dispose();
    _speech.removeListener(_speechChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOcr = attachment?.type == NoteType.image;
    final hasTranscription = attachment?.type == NoteType.audio;
    return DefaultTabController(
      length: hasOcr || hasTranscription ? 3 : 2,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title.isEmpty ? entry.primaryType.label : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                attachment?.fileName ?? entry.primaryType.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            if (_file != null)
              IconButton(
                tooltip: '用其他应用打开',
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            if (widget.attachment == null)
              IconButton(
                tooltip: '编辑信息',
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
            const SizedBox(width: 6),
          ],
          bottom: TabBar(
            dividerColor: AppColors.line,
            indicatorColor: AppColors.moss,
            indicatorWeight: 2,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.muted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: '预览'),
              if (hasOcr) const Tab(text: '识别文字'),
              if (hasTranscription) const Tab(text: '转写文字'),
              const Tab(text: '信息'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PreviewTab(
              attachment: attachment,
              file: _file,
              video: _video,
              audio: _audio,
              audioPosition: _audioPosition,
              audioDuration: _audioDuration,
            ),
            if (hasOcr) _buildOcrTab(),
            if (hasTranscription) _buildTranscriptionTab(),
            _buildInfoTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrTab() {
    final text = attachment?.ocrText?.trim() ?? '';
    final hasRecognizedText = text.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '图片中的文字',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (hasRecognizedText)
              IconButton.filledTonal(
                tooltip: '复制全部',
                onPressed: _copyOcr,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: hasRecognizedText ? '重新识别' : '识别文字',
              onPressed: _recognizing ? null : _recognizeText,
              icon: _recognizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!hasRecognizedText)
          EmptyState(
            icon: Icons.text_snippet_outlined,
            message: '暂无识别文字',
            description: '需要时可对这张图片进行本地文字识别',
            actionLabel: _recognizing ? '正在识别…' : '识别文字',
            onAction: _recognizing ? null : _recognizeText,
          )
        else
          SelectableText(
            text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.72,
              color: AppColors.ink,
            ),
          ),
      ],
    );
  }

  Widget _buildTranscriptionTab() {
    final text = attachment?.transcript?.trim() ?? '';
    final job = _speech.jobFor(attachment?.filePath ?? '');
    final modelInstalled = _speechModel?.installed == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '录音转写',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (text.isNotEmpty) ...[
              IconButton.filledTonal(
                tooltip: '编辑文字',
                onPressed: _editTranscript,
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '复制全部',
                onPressed: _copyTranscript,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.moss),
            SizedBox(width: 5),
            Text(
              '完全在本机处理，音频不会离开设备',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_importingModel)
          _TranscriptionProgressCard(
            title: _modelOperationLabel,
            subtitle: _modelTransferDescription(),
            progress: _modelImportProgress ?? 0,
            onCancel: _modelOperationLabel.contains('下载')
                ? () => setState(() => _cancelModelDownload = true)
                : null,
          )
        else if (!modelInstalled)
          EmptyState(
            icon: Icons.memory_rounded,
            message: '需要离线识别模型',
            description: '模型独立保存在本机，不增加笔记备份大小',
            actionLabel: '在线下载约 228 MB',
            onAction: _downloadSpeechModel,
          )
        else if (job?.isRunning == true)
          _TranscriptionProgressCard(
            title: _statusText(job!.status),
            subtitle: job.partialText.isEmpty
                ? '可以离开此页面继续使用笔记'
                : job.partialText,
            progress: job.progress,
            onCancel: () => _speech.cancel(job.filePath),
          )
        else if (job?.status == TranscriptionStatus.failed)
          EmptyState(
            icon: Icons.error_outline_rounded,
            message: '转写没有完成',
            description: job?.errorMessage ?? '请稍后重试',
            actionLabel: '重新转写',
            onAction: _startTranscription,
          )
        else if (job?.status == TranscriptionStatus.canceled && text.isEmpty)
          EmptyState(
            icon: Icons.pause_circle_outline_rounded,
            message: '已取消转写',
            description: '录音文件没有受到影响',
            actionLabel: '重新转写',
            onAction: _startTranscription,
          )
        else if (text.isEmpty)
          EmptyState(
            icon: Icons.text_snippet_outlined,
            message: '暂无转写文字',
            description: '需要时再启动本地识别，不会自动处理录音',
            actionLabel: '本地转写',
            onAction: _startTranscription,
          )
        else ...[
          SelectableText(
            text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.72,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _startTranscription,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新转写'),
          ),
        ],
        if (modelInstalled && job?.isRunning != true) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('speaker-diarization-transcription'),
            onPressed: _startSpeakerTranscription,
            icon: const Icon(Icons.groups_2_outlined),
            label: Text(
              _speakerModel?.installed == true
                  ? '区分说话人转写'
                  : '区分说话人转写 · 需 44.4 MB 模型',
            ),
          ),
        ],
        if (modelInstalled && job?.isRunning != true) ...[
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: _openModelManager,
                  icon: const Icon(Icons.memory_rounded),
                  label: Text('管理模型 · ${_formatSize(_speechModel!.sizeBytes)}'),
                ),
              ),
              TextButton.icon(
                onPressed: _removeSpeechModel,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('移除'),
              ),
            ],
          ),
        ] else if (!modelInstalled && !_importingModel) ...[
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _importSpeechModel,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('从文件导入'),
                ),
                TextButton.icon(
                  onPressed: _openModelManager,
                  icon: const Icon(Icons.memory_rounded),
                  label: const Text('查看全部模型'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _statusText(TranscriptionStatus status) => switch (status) {
    TranscriptionStatus.preparing => '正在准备本地转写',
    TranscriptionStatus.decoding => '正在读取音频',
    TranscriptionStatus.diarizing => '正在区分说话人',
    TranscriptionStatus.recognizing => '正在本地识别',
    TranscriptionStatus.saving => '正在保存转写文字',
    _ => '正在处理',
  };

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _InfoCard(
          title: '笔记信息',
          children: [
            _InfoRow('类型', attachment?.type.label ?? entry.primaryType.label),
            _InfoRow('创建', _formatDate(entry.createdAt)),
            _InfoRow('更新', _formatDate(entry.updatedAt)),
            if (entry.tags.isNotEmpty)
              _InfoRow('标签', entry.tags.map((tag) => '#$tag').join('  ')),
          ],
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: '文件信息',
          children: [
            if (attachment != null) _InfoRow('文件名', attachment!.fileName),
            if (attachment != null)
              _InfoRow('大小', _formatSize(attachment!.fileSize)),
            if (attachment?.durationMs != null)
              _InfoRow(
                '时长',
                _formatDuration(
                  Duration(milliseconds: attachment!.durationMs!),
                ),
              ),
            _InfoRow('保存状态', _file == null ? '文件不存在' : '已保存在统一目录'),
          ],
        ),
        if (entry.content?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          _InfoCard(
            title: '说明',
            children: [FkMarkdownView(data: entry.readableContent)],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  String _formatDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _PreviewTab extends StatelessWidget {
  final NoteAttachment? attachment;
  final File? file;
  final VideoPlayerController? video;
  final AudioPlayer? audio;
  final Duration audioPosition;
  final Duration audioDuration;
  const _PreviewTab({
    required this.attachment,
    required this.file,
    required this.video,
    required this.audio,
    required this.audioPosition,
    required this.audioDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return const EmptyState(
        icon: Icons.link_off_rounded,
        message: '原文件不存在',
        description: '可以保留笔记信息或将它移到回收站',
      );
    }
    return switch (attachment?.type ?? NoteType.text) {
      NoteType.image => Container(
        color: const Color(0xFF111815),
        padding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(80),
          child: Center(child: Image.file(file!, fit: BoxFit.contain)),
        ),
      ),
      NoteType.video => _VideoPreview(controller: video),
      NoteType.audio => _AudioPreview(
        player: audio,
        position: audioPosition,
        duration: audioDuration,
      ),
      NoteType.document => _DocumentPreview(
        fileName: attachment?.fileName,
        file: file!,
      ),
      NoteType.text => const SizedBox.shrink(),
    };
  }
}

class _VideoPreview extends StatelessWidget {
  final VideoPlayerController? controller;
  const _VideoPreview({required this.controller});
  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final c = controller!;
    return Container(
      color: const Color(0xFF111815),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
            const SizedBox(height: 16),
            IconButton.filled(
              onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
              iconSize: 34,
              icon: Icon(
                c.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPreview extends StatelessWidget {
  final AudioPlayer? player;
  final Duration position;
  final Duration duration;
  const _AudioPreview({
    required this.player,
    required this.position,
    required this.duration,
  });
  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 120),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              const _Waveform(active: true),
              const SizedBox(height: 30),
              Slider(
                value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                max: max,
                onChanged: player == null
                    ? null
                    : (value) =>
                          player!.seek(Duration(milliseconds: value.round())),
              ),
              Row(
                children: [
                  Text(_durationText(position)),
                  const Spacer(),
                  Text(_durationText(duration)),
                ],
              ),
              const SizedBox(height: 18),
              StreamBuilder<bool>(
                stream: player?.playingStream,
                initialData: false,
                builder: (_, snapshot) => IconButton.filled(
                  onPressed: player == null
                      ? null
                      : () => snapshot.data == true
                            ? player!.pause()
                            : player!.play(),
                  iconSize: 38,
                  icon: Icon(
                    snapshot.data == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _durationText(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Waveform extends StatelessWidget {
  final bool active;
  const _Waveform({required this.active});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(24, (index) {
        final heights = [18.0, 28.0, 42.0, 24.0, 54.0, 34.0, 48.0, 22.0];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 4,
          height: heights[index % heights.length],
          decoration: BoxDecoration(
            color: (active ? AppColors.moss : AppColors.muted).withValues(
              alpha: index.isEven ? 1 : .45,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    ),
  );
}

class _DocumentPreview extends StatelessWidget {
  final String? fileName;
  final File file;
  const _DocumentPreview({required this.fileName, required this.file});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_rounded,
              size: 64,
              color: Color(0xFF77665B),
            ),
            const SizedBox(height: 16),
            Text(
              fileName ?? '文件',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => OpenFile.open(file.path),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('用本地应用打开'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TranscriptionProgressCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  final VoidCallback? onCancel;
  const _TranscriptionProgressCard({
    required this.title,
    required this.subtitle,
    required this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: AppColors.moss,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        LinearProgressIndicator(
          value: progress <= 0 ? null : progress.clamp(0, 1),
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 13),
        Text(
          subtitle,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, height: 1.5),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onCancel, child: const Text('取消')),
          ),
        ],
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
