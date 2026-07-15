import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/note_service.dart';
import '../services/ocr_service.dart';
import '../services/speech_model_service.dart';
import '../services/speech_transcription_service.dart';
import '../services/speaker_diarization_model_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/empty_state.dart';
import '../widgets/editor_context_menu.dart';
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
  String _modelOperationLabel = '';
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
    AppFeedback.error(context, result.message);
  }

  Future<void> _copyOcr() async {
    await Clipboard.setData(ClipboardData(text: attachment?.ocrText ?? ''));
    if (mounted) {
      AppFeedback.success(context, context.l10n.recognizedTextCopied);
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
      AppFeedback.error(
        context,
        result.didFail
            ? context.l10n.ocrFailedDetail(result.errorMessage ?? '')
            : context.l10n.noClearTextRecognized,
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
    final l10n = context.l10n;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importOfflineSpeechModel),
        content: Text(l10n.importSpeechModelDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.chooseFiles),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() {
      _importingModel = true;
      _modelImportProgress = 0;
      _modelOperationLabel = l10n.importingOfflineModel;
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
        AppFeedback.success(context, l10n.offlineSpeechModelImported);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, l10n.modelImportFailed('$error'));
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
    final l10n = context.l10n;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadOfflineSpeechModelQuestion),
        content: Text(l10n.downloadSpeechModelDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.startDownload),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() {
      _importingModel = true;
      _cancelModelDownload = false;
      _modelImportProgress = 0;
      _modelOperationLabel = l10n.downloadingFromModelScope;
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
        AppFeedback.success(context, l10n.offlineSpeechModelDownloaded);
      }
    } on SpeechModelDownloadCanceled {
      if (mounted) {
        AppFeedback.show(context, l10n.downloadPausedResumable);
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(context, l10n.modelDownloadFailedDetail('$error'));
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
      if (progress.verifying) {
        _modelOperationLabel = context.l10n.finishingInstallation;
      }
    });
  }

  String _modelTransferDescription() {
    final l10n = context.l10n;
    final transferred = _formatSize(_modelTransferredBytes);
    final total = _formatSize(_modelTotalBytes);
    final amount = _downloadingModelOnline
        ? l10n.downloadedAmount(transferred)
        : l10n.importedAmount(transferred);
    if (_modelVerifying) return l10n.amountFinishingInstall(amount);
    final speed = _modelBytesPerSecond <= 0
        ? l10n.speedTesting
        : '${_formatSize(_modelBytesPerSecond.round())}/s';
    return '$amount / $total · $speed';
  }

  Future<void> _removeSpeechModel() async {
    if (_speech.jobs.any((job) => job.isRunning)) {
      AppFeedback.show(context, context.l10n.waitForTranscription);
      return;
    }
    final l10n = context.l10n;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeOfflineModelQuestion),
        content: Text(l10n.removeOfflineModelDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeModel),
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
    final l10n = context.l10n;
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
          title: Text(l10n.speakerModelRequired),
          content: Text(l10n.speakerModelDownloadDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.manage),
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
        title: Text(l10n.speakerCount),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              l10n.speakerCountDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, -1),
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(l10n.estimateAutomatically),
              subtitle: Text(l10n.estimateAutomaticallyDescription),
            ),
          ),
          for (var count = 2; count <= 8; count++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, count),
              child: Text(l10n.speakerCountOption(count)),
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
      AppFeedback.success(context, context.l10n.transcriptCopied);
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
    final l10n = context.l10n;
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
                entry.title.isEmpty
                    ? _localizedNoteType(context, entry.primaryType)
                    : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                attachment?.displayTitle ??
                    _localizedNoteType(context, entry.primaryType),
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
                tooltip: l10n.openWithAnotherApp,
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            if (widget.attachment == null)
              IconButton(
                tooltip: l10n.editInformation,
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
              Tab(text: l10n.preview),
              if (hasOcr) Tab(text: l10n.recognizedText),
              if (hasTranscription) Tab(text: l10n.transcript),
              Tab(text: l10n.information),
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
    final l10n = context.l10n;
    final text = attachment?.ocrText?.trim() ?? '';
    final hasRecognizedText = text.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.textInImage,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (hasRecognizedText)
              IconButton.filledTonal(
                tooltip: l10n.copyAll,
                onPressed: _copyOcr,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: hasRecognizedText
                  ? l10n.recognizeAgain
                  : l10n.recognizeText,
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
            message: l10n.noRecognizedText,
            description: l10n.ocrOnDemandDescription,
            actionLabel: _recognizing ? l10n.recognizing : l10n.recognizeText,
            onAction: _recognizing ? null : _recognizeText,
          )
        else
          SelectableText(
            text,
            contextMenuBuilder: buildAppEditableTextContextMenu,
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
    final l10n = context.l10n;
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
                l10n.audioTranscript,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (text.isNotEmpty) ...[
              IconButton.filledTonal(
                tooltip: l10n.editText,
                onPressed: _editTranscript,
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: l10n.copyAll,
                onPressed: _copyTranscript,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.moss,
            ),
            const SizedBox(width: 5),
            Text(
              l10n.audioStaysOnDevice,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_importingModel)
          _TranscriptionProgressCard(
            title: _modelOperationLabel.isEmpty
                ? l10n.preparingModel
                : _modelOperationLabel,
            subtitle: _modelTransferDescription(),
            progress: _modelImportProgress ?? 0,
            onCancel: _downloadingModelOnline
                ? () => setState(() => _cancelModelDownload = true)
                : null,
          )
        else if (!modelInstalled)
          EmptyState(
            icon: Icons.memory_rounded,
            message: l10n.offlineSpeechModelRequired,
            description: l10n.offlineModelBackupDescription,
            actionLabel: l10n.downloadAbout228Mb,
            onAction: _downloadSpeechModel,
          )
        else if (job?.isRunning == true)
          _TranscriptionProgressCard(
            title: _statusText(job!.status),
            subtitle: job.partialText.isEmpty
                ? l10n.backgroundTranscriptionHint
                : job.partialText,
            progress: job.progress,
            onCancel: () => _speech.cancel(job.filePath),
          )
        else if (job?.status == TranscriptionStatus.failed)
          EmptyState(
            icon: Icons.error_outline_rounded,
            message: l10n.transcriptionIncomplete,
            description: job?.errorMessage ?? l10n.tryAgainLater,
            actionLabel: l10n.transcribeAgain,
            onAction: _startTranscription,
          )
        else if (job?.status == TranscriptionStatus.canceled && text.isEmpty)
          EmptyState(
            icon: Icons.pause_circle_outline_rounded,
            message: l10n.transcriptionCanceled,
            description: l10n.recordingUnaffected,
            actionLabel: l10n.transcribeAgain,
            onAction: _startTranscription,
          )
        else if (text.isEmpty)
          EmptyState(
            icon: Icons.text_snippet_outlined,
            message: l10n.noTranscript,
            description: l10n.transcriptionOnDemandDescription,
            actionLabel: l10n.transcribeOnDevice,
            onAction: _startTranscription,
          )
        else ...[
          SelectableText(
            text,
            contextMenuBuilder: buildAppEditableTextContextMenu,
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
            label: Text(l10n.transcribeAgain),
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
                  ? l10n.speakerDiarizedTranscription
                  : l10n.speakerDiarizedTranscriptionModelRequired,
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
                  label: Text(
                    l10n.manageModelSize(_formatSize(_speechModel!.sizeBytes)),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _removeSpeechModel,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.remove),
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
                  label: Text(l10n.importFromFiles),
                ),
                TextButton.icon(
                  onPressed: _openModelManager,
                  icon: const Icon(Icons.memory_rounded),
                  label: Text(l10n.viewAllModels),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _statusText(TranscriptionStatus status) => switch (status) {
    TranscriptionStatus.preparing => context.l10n.preparingLocalTranscription,
    TranscriptionStatus.decoding => context.l10n.readingAudio,
    TranscriptionStatus.diarizing => context.l10n.separatingSpeakers,
    TranscriptionStatus.recognizing => context.l10n.recognizingOnDevice,
    TranscriptionStatus.saving => context.l10n.savingTranscriptText,
    _ => context.l10n.processing,
  };

  Widget _buildInfoTab() {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _InfoCard(
          title: l10n.noteInformation,
          children: [
            _InfoRow(
              l10n.type,
              _localizedNoteType(
                context,
                attachment?.type ?? entry.primaryType,
              ),
            ),
            _InfoRow(l10n.created, _formatDate(context, entry.createdAt)),
            _InfoRow(l10n.updated, _formatDate(context, entry.updatedAt)),
            if (entry.tags.isNotEmpty)
              _InfoRow(l10n.tags, entry.tags.map((tag) => '#$tag').join('  ')),
          ],
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: l10n.fileInformation,
          children: [
            if (attachment?.displayName?.trim().isNotEmpty == true)
              _InfoRow(l10n.attachmentTitle, attachment!.displayTitle),
            if (attachment != null)
              _InfoRow(l10n.fileName, attachment!.fileName),
            if (attachment != null)
              _InfoRow(l10n.size, _formatSize(attachment!.fileSize)),
            if (attachment?.durationMs != null)
              _InfoRow(
                l10n.duration,
                _formatDuration(
                  Duration(milliseconds: attachment!.durationMs!),
                ),
              ),
            _InfoRow(
              l10n.saveStatus,
              _file == null ? l10n.fileMissing : l10n.savedInUnifiedDirectory,
            ),
          ],
        ),
        if (entry.content?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          _InfoCard(
            title: l10n.description,
            children: [FkMarkdownView(data: entry.readableContent)],
          ),
        ],
      ],
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(date)}  '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  String _localizedNoteType(BuildContext context, NoteType type) =>
      switch (type) {
        NoteType.text => context.l10n.note,
        NoteType.image => context.l10n.image,
        NoteType.audio => context.l10n.audio,
        NoteType.video => context.l10n.video,
        NoteType.document => context.l10n.file,
      };
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
      return EmptyState(
        icon: Icons.link_off_rounded,
        message: context.l10n.originalFileMissing,
        description: context.l10n.missingFileDescription,
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
        fileName: attachment?.displayTitle,
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
              fileName ?? context.l10n.file,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => OpenFile.open(file.path),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(context.l10n.openWithLocalApp),
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
            child: TextButton(
              onPressed: onCancel,
              child: Text(context.l10n.cancel),
            ),
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
