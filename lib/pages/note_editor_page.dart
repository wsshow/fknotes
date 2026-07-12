import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/language_model_service.dart';
import '../services/local_model_manager.dart';
import '../services/kokoro_tts_model_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/realtime_dictation_service.dart';
import '../services/streaming_speech_model_service.dart';
import '../services/video_import_service.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/note_assistant_sheet.dart';
import '../widgets/note_block_editor.dart';
import '../widgets/note_card.dart';
import 'media_detail_page.dart';
import 'model_management_page.dart';
import 'record_audio_page.dart';

class NoteEditorPage extends StatefulWidget {
  final NoteEntry? existingEntry;
  final List<String> initialImportJobIds;
  final List<String> initialVideoJobIds;

  const NoteEditorPage({
    super.key,
    this.existingEntry,
    this.initialImportJobIds = const [],
    this.initialVideoJobIds = const [],
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _title;
  late final TextEditingController _content;
  String? _richContent;
  late String _lastTitleText;
  late String _lastContentText;
  final _blockEditorKey = GlobalKey<NoteBlockEditorState>();
  late List<String> _tags;
  late bool _favorite;
  late bool _pinned;
  late List<NoteAttachment> _attachments;
  final List<NoteAttachment> _removedAttachments = [];
  final _storage = FileStorageService.instance;
  final _dictation = RealtimeDictationService.instance;
  final _readAloud = NoteReadAloudService.instance;
  late final Set<String> _importJobIds;
  NoteProvider? _provider;
  NoteEntry? _entry;
  Timer? _autosave;
  bool _changed = false;
  bool _saving = false;
  bool _saveAgain = false;
  bool _importing = false;
  bool _dictationAnchored = false;
  String _dictationInsertedText = '';
  bool _recoveringDictationFailure = false;
  bool _dictationOperationPending = false;
  bool _showDictationDiagnostics = false;
  bool _dictationDiagnosticsCollapsed = false;
  double _dictationDiagnosticsTop = 72;
  double _dictationDiagnosticsLeft = 12;
  double _dictationDiagnosticsWidth = 400;
  double _dictationDiagnosticsHeight = 380;

  bool get _isEditing => _entry != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final entry = widget.existingEntry;
    _entry = entry;
    _importJobIds = {
      ...widget.initialImportJobIds,
      ...widget.initialVideoJobIds,
    };
    _title = TextEditingController(text: entry?.title ?? '');
    _content = TextEditingController(text: entry?.content ?? '');
    _richContent = entry?.richContent;
    _lastTitleText = _title.text;
    _lastContentText = _content.text;
    _tags = [...?entry?.tags];
    _favorite = entry?.isFavorite ?? false;
    _pinned = entry?.isPinned ?? false;
    _attachments = [...?entry?.allAttachments];
    _title.addListener(_onTitleChanged);
    _content.addListener(_onContentChanged);
    _dictation.addListener(_handleDictationChanged);
    _readAloud.addListener(_handleReadAloudChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NoteProvider>();
    if (identical(_provider, provider)) return;
    _provider?.removeListener(_handleProviderChanged);
    _provider = provider..addListener(_handleProviderChanged);
    final noteId = _entry?.id;
    if (noteId != null) {
      _importJobIds.addAll(
        provider.attachmentImportsForNote(noteId).map((job) => job.id),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleProviderChanged(),
    );
  }

  void _onTitleChanged() {
    if (_title.text == _lastTitleText) return;
    _lastTitleText = _title.text;
    _markChanged();
  }

  void _onContentChanged() {
    if (_content.text == _lastContentText) return;
    _lastContentText = _content.text;
    _markChanged();
  }

  void _onRichContentChanged(String value) {
    if (_richContent == value) return;
    _richContent = value;
    _markChanged();
    if (_dictationAnchored &&
        _dictationInsertedText != _dictation.committedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_dictationAnchored) return;
        _insertCommittedDictation(_dictation.committedText);
      });
    }
  }

  void _markChanged() {
    if (!_changed && mounted) {
      setState(() => _changed = true);
    } else {
      _changed = true;
    }
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 700), _persist);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _provider?.removeListener(_handleProviderChanged);
    _dictation.removeListener(_handleDictationChanged);
    _readAloud.removeListener(_handleReadAloudChanged);
    if (_readAloud.status != ReadAloudStatus.idle) {
      unawaited(_readAloud.stop());
    }
    if (_dictation.isActive) unawaited(_dictation.cancel());
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _handleDictationChanged() {
    if (!mounted) return;
    if (_dictation.status == RealtimeDictationStatus.failed &&
        _dictationAnchored &&
        !_dictationOperationPending &&
        !_recoveringDictationFailure) {
      _recoveringDictationFailure = true;
      unawaited(_recoverFromDictationFailure());
      return;
    }
    if (_dictationAnchored) {
      _insertCommittedDictation(_dictation.committedText);
    }
    setState(() {});
  }

  void _handleReadAloudChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleReadAloud() async {
    if (_readAloud.isActive || _readAloud.status == ReadAloudStatus.failed) {
      await _readAloud.stop();
      return;
    }
    final model = await KokoroTtsModelService.instance.inspect();
    if (!model.installed) {
      if (!mounted) return;
      final openModels = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要离线朗读模型'),
          content: const Text(
            'Kokoro 中英双语 INT8 首次使用需下载约 140.2 MB。'
            '下载后，笔记朗读全程断网可用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('管理模型'),
            ),
          ],
        ),
      );
      if (openModels == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ModelManagementPage(
              focusModelId: KokoroTtsModelService.modelId,
            ),
          ),
        );
      }
      return;
    }
    final text = [
      _title.text.trim(),
      _content.text.trim(),
    ].where((part) => part.isNotEmpty).join('。');
    try {
      await _readAloud.speak(text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readAloud.errorMessage ?? '无法朗读这篇笔记')),
        );
      }
    }
  }

  void _insertCommittedDictation(String committed) {
    if (committed == _dictationInsertedText) return;
    if (!committed.startsWith(_dictationInsertedText)) {
      // Committed recognition is expected to grow monotonically. If a native
      // runtime ever revises it, wait for the final stop result rather than
      // duplicating or overwriting text the user may be editing manually.
      return;
    }
    final addition = committed.substring(_dictationInsertedText.length);
    if (addition.trim().isEmpty) {
      _dictationInsertedText = committed;
      return;
    }
    final inserted =
        _blockEditorKey.currentState?.insertDictationTextAtCaret(addition) ??
        false;
    if (inserted) _dictationInsertedText = committed;
  }

  Future<void> _recoverFromDictationFailure() async {
    final message = _dictation.errorMessage ?? '实时听写没有完成';
    _dictationAnchored = false;
    _dictationInsertedText = '';
    await _dictation.cancel();
    _recoveringDictationFailure = false;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _dictation.status == RealtimeDictationStatus.listening) {
      unawaited(_cancelDictation());
    }
  }

  Future<void> _toggleDictation() async {
    if (_dictation.status == RealtimeDictationStatus.listening) {
      await _stopDictation();
      return;
    }
    if (_dictation.isActive) return;
    final installed = await StreamingSpeechModelService.instance.inspect();
    if (!installed.installed) {
      if (!mounted) return;
      final definition = LocalModelManager.instance.modelOf(installed.modelId);
      final downloadSize =
          '${(definition.downloadSizeBytes / 1048576).toStringAsFixed(1)} MB';
      final openModels = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要实时语音模型'),
          content: Text(
            '当前选择的是${definition.name}，首次使用需下载约 $downloadSize。'
            '下载完成后，听写全程断网可用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('管理模型'),
            ),
          ],
        ),
      );
      if (openModels == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ModelManagementPage(focusModelId: installed.modelId),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final anchored =
        _blockEditorKey.currentState?.prepareDictationInsertion() ?? false;
    if (!anchored) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先将光标放在文字区域')));
      return;
    }
    _dictationAnchored = true;
    _dictationInsertedText = '';
    _dictationOperationPending = true;
    try {
      await _dictation.start();
      HapticFeedback.mediumImpact();
    } catch (_) {
      _dictationAnchored = false;
      _dictationInsertedText = '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_dictation.errorMessage ?? '无法开始实时听写')),
        );
      }
    } finally {
      _dictationOperationPending = false;
    }
  }

  Future<void> _openLocalAssistant() async {
    if (_title.text.trim().isEmpty && _content.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先写下一些笔记内容')));
      return;
    }

    try {
      final models = LanguageModelService.instance;
      final selectedId = await models.selectedModelId();
      final installed = await models.inspect(selectedId);
      if (!mounted) return;
      if (!installed.installed) {
        final downloadSize =
            '${(models.downloadSizeBytes(selectedId) / 1073741824).toStringAsFixed(1)} GB';
        final openModels = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('需要本地语言模型'),
            content: Text(
              '当前选择的是 ${models.displayName(selectedId)}，首次使用需下载约 '
              '$downloadSize。下载完成后，笔记内容只在本机处理。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后再说'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('管理模型'),
              ),
            ],
          ),
        );
        if (openModels == true && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ModelManagementPage(focusModelId: selectedId),
            ),
          );
        }
        return;
      }

      final task = await showNoteAssistantTaskSheet(context);
      if (task == null || !mounted) return;
      final generated = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => NoteAssistantResultSheet(
          task: task,
          title: _title.text,
          content: _content.text,
        ),
      );
      if (generated == null || !mounted) return;
      final inserted =
          _blockEditorKey.currentState?.appendAssistantText(
            heading: task.resultHeading,
            text: generated,
          ) ??
          false;
      if (inserted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成内容已插入笔记末尾')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法启动本地助手：$error')));
    }
  }

  Future<void> _stopDictation() async {
    _dictationOperationPending = true;
    try {
      final result = await _dictation.stop();
      _finalizeCommittedDictation(result);
      _dictationAnchored = false;
      _dictationInsertedText = '';
      HapticFeedback.mediumImpact();
    } catch (_) {
      _dictationAnchored = false;
      _dictationInsertedText = '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_dictation.errorMessage ?? '实时听写没有完成')),
        );
      }
    } finally {
      _dictationOperationPending = false;
    }
  }

  void _finalizeCommittedDictation(String result) {
    if (result.startsWith(_dictationInsertedText)) {
      _insertCommittedDictation(result);
      return;
    }
    final replaced =
        _blockEditorKey.currentState?.replaceDictationTextBeforeCaret(
          previous: _dictationInsertedText,
          replacement: result,
        ) ??
        false;
    if (replaced) _dictationInsertedText = result;
  }

  Future<void> _cancelDictation() async {
    await _dictation.cancel();
    _dictationAnchored = false;
    _dictationInsertedText = '';
    HapticFeedback.selectionClick();
  }

  void _handleProviderChanged() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;
    final noteId = _entry?.id;
    if (noteId != null) {
      _importJobIds.addAll(
        provider.attachmentImportsForNote(noteId).map((job) => job.id),
      );
    }
    final jobsToDismiss = <String>[];
    var changed = _importJobIds.isNotEmpty;
    for (final jobId in _importJobIds.toList()) {
      final job = provider.attachmentImportJob(jobId);
      if (job == null || job.status == AttachmentImportStatus.canceled) {
        _importJobIds.remove(jobId);
        jobsToDismiss.add(jobId);
        changed = true;
        continue;
      }
      if (!job.committed || job.filePath == null || job.noteId == null) {
        continue;
      }
      final refreshed = provider.getEntryById(job.noteId!);
      final imported = refreshed?.allAttachments
          .where((item) => item.filePath == job.filePath)
          .firstOrNull;
      if (imported != null &&
          !_attachments.any((item) => item.filePath == imported.filePath)) {
        _attachments.add(imported);
        _entry = (_entry ?? refreshed)!.copyWith(attachments: _attachments);
      }
      _importJobIds.remove(jobId);
      jobsToDismiss.add(jobId);
      changed = true;
    }
    if (changed) setState(() {});
    if (jobsToDismiss.isNotEmpty) {
      scheduleMicrotask(() {
        for (final jobId in jobsToDismiss) {
          provider.acknowledgeAttachmentImport(jobId);
        }
      });
    }
  }

  Future<bool> _persist() async {
    if (_saving) {
      _saveAgain = true;
      return false;
    }
    final title = _title.text.trim();
    final content = _content.text;
    if (title.isEmpty && content.trim().isEmpty && _attachments.isEmpty) {
      return true;
    }
    if (mounted) setState(() => _saving = true);
    final provider = context.read<NoteProvider>();
    final now = DateTime.now();
    var success = false;
    try {
      if (_entry != null) {
        final updated = _entry!.copyWith(
          type: _attachments.isEmpty ? NoteType.text : _attachments.first.type,
          title: title,
          content: content,
          richContent: _richContent,
          tags: _tags,
          isFavorite: _favorite,
          isPinned: _pinned,
          updatedAt: now,
          attachments: _orderedAttachments,
        );
        await provider.updateEntry(updated);
        _entry = updated;
      } else {
        final created = NoteEntry(
          type: _attachments.isEmpty ? NoteType.text : _attachments.first.type,
          title: title,
          content: content,
          richContent: _richContent,
          tags: _tags,
          isFavorite: _favorite,
          isPinned: _pinned,
          createdAt: now,
          updatedAt: now,
          attachments: _orderedAttachments,
        );
        final id = await provider.addEntry(created);
        _entry = created.copyWith(id: id);
      }
      _changed = false;
      for (final attachment in _removedAttachments) {
        await _storage.deleteFile(attachment.filePath);
        await _storage.deleteFile(attachment.thumbnailPath);
      }
      _removedAttachments.clear();
      success = true;
    } catch (error) {
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('自动保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (_saveAgain) {
      _saveAgain = false;
      return _persist();
    }
    return success;
  }

  List<NoteAttachment> get _orderedAttachments => [
    for (var index = 0; index < _attachments.length; index++)
      _attachments[index].copyWith(sortOrder: index),
  ];

  Future<void> _showAddContentSheet() async {
    if (_importing) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '添加到笔记',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _AddContentAction(
                    icon: Icons.photo_library_outlined,
                    label: '图片',
                    onTap: () => _runAfterSheet(sheetContext, _pickImages),
                  ),
                  _AddContentAction(
                    icon: Icons.camera_alt_outlined,
                    label: '拍照',
                    onTap: () => _runAfterSheet(sheetContext, _takePhoto),
                  ),
                  _AddContentAction(
                    icon: Icons.mic_none_rounded,
                    label: '录音',
                    onTap: () => _runAfterSheet(sheetContext, _recordAudio),
                  ),
                  _AddContentAction(
                    icon: Icons.audio_file_outlined,
                    label: '音频',
                    onTap: () => _runAfterSheet(sheetContext, _pickAudio),
                  ),
                  _AddContentAction(
                    icon: Icons.video_file_outlined,
                    label: '视频',
                    onTap: () => _runAfterSheet(sheetContext, _pickVideo),
                  ),
                  _AddContentAction(
                    icon: Icons.attach_file_rounded,
                    label: '文件',
                    onTap: () => _runAfterSheet(sheetContext, _pickDocument),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAttachmentReferenceSheet() async {
    if (_attachments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先为笔记添加图片、录音或文件')));
      return;
    }
    final selected = await showModalBottomSheet<NoteAttachment>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '引用附件',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                '引用块与原附件保持联动，不会复制文件',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (_, index) {
                    final attachment = _attachments[index];
                    final color = NoteCard.colorForType(attachment.type);
                    return ListTile(
                      onTap: () => Navigator.pop(sheetContext, attachment),
                      tileColor: color.withValues(alpha: .07),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          NoteCard.iconForType(attachment.type),
                          color: color,
                          size: 21,
                        ),
                      ),
                      title: Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${attachment.type.label} · 插入正文'),
                      trailing: const Icon(Icons.add_link_rounded),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      _blockEditorKey.currentState?.insertAttachmentReference(
        selected.filePath,
      );
    }
  }

  void _runAfterSheet(BuildContext sheetContext, Future<void> Function() task) {
    Navigator.pop(sheetContext);
    Future<void>.delayed(const Duration(milliseconds: 220), task);
  }

  Future<void> _pickImages() => _pickAttachment(NoteType.image);

  Future<void> _takePhoto() => _pickAttachment(NoteType.image, camera: true);

  Future<void> _pickVideo() => _pickAttachment(NoteType.video);

  Future<void> _pickAudio() => _pickAttachment(NoteType.audio);

  Future<void> _pickDocument() => _pickAttachment(NoteType.document);

  Future<void> _pickAttachment(NoteType type, {bool camera = false}) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final provider = context.read<NoteProvider>();
      final jobs = await provider.startAttachmentImport(
        type,
        noteId: _entry?.id,
        camera: camera,
      );
      if (jobs.isEmpty || !mounted) return;
      final draft = jobs.first.noteId == null
          ? null
          : provider.getEntryById(jobs.first.noteId!);
      setState(() {
        _importJobIds.addAll(jobs.map((job) => job.id));
        if (_entry == null && draft != null) {
          _entry = draft;
          if (_title.text.trim().isEmpty) {
            _lastTitleText = draft.title;
            _title.text = draft.title;
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is PlatformException
          ? error.message ?? '${type.label}导入失败'
          : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeAttachmentImport(AttachmentImportJob job) async {
    final provider = context.read<NoteProvider>();
    await provider.removeAttachmentImport(job.id);
    if (mounted) setState(() => _importJobIds.remove(job.id));
  }

  Future<void> _retryAttachmentImport(AttachmentImportJob job) async {
    await _removeAttachmentImport(job);
    if (mounted) await _pickAttachment(job.type);
  }

  Future<void> _recordAudio() async {
    final attachment = await Navigator.push<NoteAttachment>(
      context,
      MaterialPageRoute(
        builder: (_) => const RecordAudioPage(returnAttachment: true),
      ),
    );
    if (attachment != null) _addAttachments([attachment]);
  }

  void _addAttachments(List<NoteAttachment> items) {
    if (!mounted || items.isEmpty) return;
    setState(() {
      _attachments.addAll(items);
      _changed = true;
    });
    _scheduleAutosave();
  }

  void _moveAttachment(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _attachments.length) return;
    setState(() {
      final item = _attachments.removeAt(index);
      _attachments.insert(target, item);
      _changed = true;
    });
    _scheduleAutosave();
  }

  void _removeAttachment(int index) {
    setState(() {
      _removedAttachments.add(_attachments.removeAt(index));
      _changed = true;
    });
    _scheduleAutosave();
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    _autosave?.cancel();
    if (_changed && !await _persist()) return;
    final entry = _entry;
    if (entry == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaDetailPage(entry: entry, attachment: attachment),
      ),
    );
    if (!mounted || entry.id == null) return;
    final refreshed = context.read<NoteProvider>().getEntryById(entry.id!);
    if (refreshed != null) {
      setState(() {
        _entry = refreshed;
        _attachments = [...refreshed.allAttachments];
      });
    }
  }

  Future<void> _close() async {
    _autosave?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final saved = !_changed || await _persist();
    if (saved && mounted) Navigator.pop(context);
  }

  Future<void> _editTags() async {
    final tags = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TagEditorSheet(initialTags: _tags),
    );
    if (tags != null && mounted) {
      setState(() {
        _tags = tags;
        _changed = true;
      });
      _scheduleAutosave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final diagnosticsWidth = _dictationDiagnosticsWidth.clamp(
      280.0,
      screenSize.width - 24,
    );
    final diagnosticsHeight = _dictationDiagnosticsHeight.clamp(
      220.0,
      screenSize.height - _dictationDiagnosticsTop - 12,
    );
    final provider = context.read<NoteProvider>();
    final importJobs = _importJobIds
        .map(provider.attachmentImportJob)
        .whereType<AttachmentImportJob>()
        .toList(growable: false);
    final hasAttachmentContent =
        _attachments.isNotEmpty || importJobs.isNotEmpty;
    final type = _attachments.isNotEmpty
        ? _attachments.first.type
        : importJobs.isNotEmpty
        ? importJobs.first.type
        : NoteType.text;
    final typeColor = NoteCard.colorForType(type);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          leading: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: typeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEditing ? '编辑笔记' : '新笔记',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _content,
                    builder: (context, value, child) => Text(
                      '${_saving
                          ? '正在保存…'
                          : _changed
                          ? '本地草稿'
                          : '已保存在本机'} · '
                      '${NoteBlockCodec.visibleCharacterCount(value.text)} 字',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('note-read-aloud'),
              tooltip: _readAloud.isActive ? '停止朗读' : '朗读笔记',
              onPressed: _toggleReadAloud,
              icon: _readAloud.status == ReadAloudStatus.generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _readAloud.isActive
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                    ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多笔记操作',
              onSelected: (value) {
                HapticFeedback.selectionClick();
                if (value == 'assistant') {
                  unawaited(_openLocalAssistant());
                  return;
                }
                setState(() {
                  if (value == 'favorite') _favorite = !_favorite;
                  if (value == 'pin') _pinned = !_pinned;
                  _changed = true;
                });
                _scheduleAutosave();
              },
              itemBuilder: (_) => [
                AppPopupMenuItem.action(
                  value: 'assistant',
                  icon: Icons.auto_awesome_rounded,
                  label: '本地助手',
                ),
                AppPopupMenuItem.action(
                  value: 'favorite',
                  icon: _favorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: _favorite ? '取消收藏' : '收藏',
                ),
                AppPopupMenuItem.action(
                  value: 'pin',
                  icon: Icons.vertical_align_top_rounded,
                  label: _pinned ? '取消置顶' : '置顶',
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: const Key('note-editor-scroll-surface'),
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _blockEditorKey.currentState?.focusAtEnd(),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _title,
                                contextMenuBuilder: buildEditorContextMenu,
                                maxLines: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  fontFamily: 'serif',
                                  fontSize: 28,
                                  height: 1.22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '标题',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final tag in _tags)
                                    InputChip(
                                      label: Text('#$tag'),
                                      onDeleted: () {
                                        setState(() {
                                          _tags.remove(tag);
                                          _changed = true;
                                        });
                                        _scheduleAutosave();
                                      },
                                    ),
                                  ActionChip(
                                    avatar: const Icon(
                                      Icons.add_rounded,
                                      size: 17,
                                    ),
                                    label: Text(_tags.isEmpty ? '添加标签' : '标签'),
                                    onPressed: _editTags,
                                  ),
                                ],
                              ),
                              if (hasAttachmentContent) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '笔记内容',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_attachments.length + importJobs.length} 项附件',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (
                                  var index = 0;
                                  index < importJobs.length;
                                  index++
                                ) ...[
                                  _AttachmentImportTile(
                                    job: importJobs[index],
                                    onCancel: () => _removeAttachmentImport(
                                      importJobs[index],
                                    ),
                                    onRetry: () => _retryAttachmentImport(
                                      importJobs[index],
                                    ),
                                    onRemove: () => _removeAttachmentImport(
                                      importJobs[index],
                                    ),
                                  ),
                                  if (index < importJobs.length - 1 ||
                                      _attachments.isNotEmpty)
                                    const SizedBox(height: 8),
                                ],
                                for (
                                  var index = 0;
                                  index < _attachments.length;
                                  index++
                                ) ...[
                                  _AttachmentEditorTile(
                                    attachment: _attachments[index],
                                    onOpen: () =>
                                        _openAttachment(_attachments[index]),
                                    onReference: () => _blockEditorKey
                                        .currentState
                                        ?.insertAttachmentReference(
                                          _attachments[index].filePath,
                                        ),
                                    canMoveUp: index > 0,
                                    canMoveDown:
                                        index < _attachments.length - 1,
                                    onMoveUp: () => _moveAttachment(index, -1),
                                    onMoveDown: () => _moveAttachment(index, 1),
                                    onRemove: () => _removeAttachment(index),
                                  ),
                                  if (index < _attachments.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Divider(),
                              ),
                              NoteBlockEditor(
                                key: _blockEditorKey,
                                controller: _content,
                                initialRichContent: _richContent,
                                onRichContentChanged: _onRichContentChanged,
                                attachments: _attachments,
                                onOpenAttachment: _openAttachment,
                                minLines: hasAttachmentContent ? 10 : 16,
                                hintText: hasAttachmentContent
                                    ? '添加说明、想法或摘要…'
                                    : '开始记录…',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.line)),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                      child: TextFieldTapRegion(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_dictation.isActive ||
                                _dictation.status ==
                                    RealtimeDictationStatus.failed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LiveDictationBar(
                                  service: _dictation,
                                  onCancel: _cancelDictation,
                                  onShowDiagnostics: kDebugMode
                                      ? () => setState(
                                          () =>
                                              _showDictationDiagnostics = true,
                                        )
                                      : null,
                                  onFinish:
                                      _dictation.status ==
                                          RealtimeDictationStatus.listening
                                      ? _stopDictation
                                      : null,
                                ),
                              ),
                            Row(
                              children: [
                                IconButton.filled(
                                  tooltip: '添加图片、录音或文件',
                                  onPressed: _importing || _dictation.isActive
                                      ? null
                                      : _showAddContentSheet,
                                  icon: _importing
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.add_rounded),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _ScrollableEditorToolbar(
                                    child: _EditorToolbar(
                                      editorKey: _blockEditorKey,
                                      onReferenceAttachment:
                                          _showAttachmentReferenceSheet,
                                      onDictation: _toggleDictation,
                                      dictationStatus: _dictation.status,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (kDebugMode && _showDictationDiagnostics)
              Positioned(
                top: _dictationDiagnosticsTop,
                left: _dictationDiagnosticsLeft,
                width: diagnosticsWidth,
                child: _DictationDiagnosticsOverlay(
                  service: _dictation,
                  collapsed: _dictationDiagnosticsCollapsed,
                  height: diagnosticsHeight,
                  onMove: (delta) {
                    setState(() {
                      final panelHeight = _dictationDiagnosticsCollapsed
                          ? 72.0
                          : diagnosticsHeight;
                      final maxLeft = screenSize.width - diagnosticsWidth - 12;
                      final maxTop = screenSize.height - panelHeight - 12;
                      _dictationDiagnosticsLeft =
                          (_dictationDiagnosticsLeft + delta.dx).clamp(
                            12.0,
                            maxLeft < 12 ? 12.0 : maxLeft,
                          );
                      _dictationDiagnosticsTop =
                          (_dictationDiagnosticsTop + delta.dy).clamp(
                            12.0,
                            maxTop < 12 ? 12.0 : maxTop,
                          );
                    });
                  },
                  onResize: (delta) {
                    setState(() {
                      final maxWidth =
                          screenSize.width - _dictationDiagnosticsLeft - 12;
                      final maxHeight =
                          screenSize.height - _dictationDiagnosticsTop - 12;
                      _dictationDiagnosticsWidth =
                          (_dictationDiagnosticsWidth + delta.dx).clamp(
                            280.0,
                            maxWidth < 280 ? 280.0 : maxWidth,
                          );
                      _dictationDiagnosticsHeight =
                          (_dictationDiagnosticsHeight + delta.dy).clamp(
                            220.0,
                            maxHeight < 220 ? 220.0 : maxHeight,
                          );
                    });
                  },
                  onToggleCollapsed: () => setState(() {
                    _dictationDiagnosticsCollapsed =
                        !_dictationDiagnosticsCollapsed;
                  }),
                  onClose: () =>
                      setState(() => _showDictationDiagnostics = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableEditorToolbar extends StatefulWidget {
  final Widget child;

  const _ScrollableEditorToolbar({required this.child});

  @override
  State<_ScrollableEditorToolbar> createState() =>
      _ScrollableEditorToolbarState();
}

class _ScrollableEditorToolbarState extends State<_ScrollableEditorToolbar> {
  final _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshEdges);
  }

  void _refreshEdges() {
    if (!_controller.hasClients) return;
    final left = _controller.offset > 1;
    final right = _controller.offset < _controller.position.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshEdges)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshEdges();
    });
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
        if (_canScrollLeft)
          const Positioned.fill(
            right: null,
            child: _ToolbarEdgeFade(left: true),
          ),
        if (_canScrollRight)
          const Positioned.fill(
            left: null,
            child: _ToolbarEdgeFade(left: false),
          ),
      ],
    );
  }
}

class _ToolbarEdgeFade extends StatelessWidget {
  final bool left;

  const _ToolbarEdgeFade({required this.left});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [AppColors.surface, Color(0x00FFFDFC)],
        ),
      ),
    ),
  );
}

class _TagEditorSheet extends StatefulWidget {
  final List<String> initialTags;

  const _TagEditorSheet({required this.initialTags});

  @override
  State<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<_TagEditorSheet> {
  late final TextEditingController _controller;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTags.join(', '));
    _tags = _parseTags(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static List<String> _parseTags(String value) => value
      .split(RegExp('[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .take(8)
      .toList();

  void _changed(String value) => setState(() => _tags = _parseTags(value));

  void _remove(String tag) {
    _tags = [..._tags]..remove(tag);
    final value = _tags.join(', ');
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() {});
  }

  void _finish() => Navigator.pop(context, _parseTags(_controller.text));

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '编辑标签',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_tags.length}/8',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '使用逗号分隔多个标签，重复标签会自动合并。',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('note-tags-field'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: _changed,
                onSubmitted: (_) => _finish(),
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '例如：工作, 灵感, 稍后阅读',
                ),
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text('#$tag'),
                        onDeleted: () => _remove(tag),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('save-note-tags'),
                      onPressed: _finish,
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatefulWidget {
  final GlobalKey<NoteBlockEditorState> editorKey;
  final VoidCallback onReferenceAttachment;
  final VoidCallback onDictation;
  final RealtimeDictationStatus dictationStatus;

  const _EditorToolbar({
    required this.editorKey,
    required this.onReferenceAttachment,
    required this.onDictation,
    required this.dictationStatus,
  });

  @override
  State<_EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<_EditorToolbar> {
  ValueNotifier<NoteBlockType>? _activeType;
  ValueNotifier<NoteEditorFormatState>? _activeFormat;
  ValueNotifier<NoteHistoryState>? _historyState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editor = widget.editorKey.currentState;
      final typeNotifier = editor?.activeType;
      final formatNotifier = editor?.activeFormat;
      final historyNotifier = editor?.historyState;
      if (identical(typeNotifier, _activeType) &&
          identical(formatNotifier, _activeFormat) &&
          identical(historyNotifier, _historyState)) {
        return;
      }
      _activeType?.removeListener(_refresh);
      _activeFormat?.removeListener(_refresh);
      _historyState?.removeListener(_refresh);
      _activeType = typeNotifier?..addListener(_refresh);
      _activeFormat = formatNotifier?..addListener(_refresh);
      _historyState = historyNotifier?..addListener(_refresh);
      _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _activeType?.removeListener(_refresh);
    _activeFormat?.removeListener(_refresh);
    _historyState?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeType?.value ?? NoteBlockType.paragraph;
    final format = _activeFormat?.value ?? const NoteEditorFormatState();
    final history = _historyState?.value ?? const NoteHistoryState();
    final editor = widget.editorKey.currentState;
    final dictating =
        widget.dictationStatus == RealtimeDictationStatus.listening;
    final dictationBusy =
        widget.dictationStatus == RealtimeDictationStatus.preparing ||
        widget.dictationStatus == RealtimeDictationStatus.stopping;
    return Row(
      children: [
        _EditorToolButton(
          tooltip: dictating ? '停止实时听写' : '实时语音输入',
          icon: dictating ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
          selected: dictating,
          onPressed: dictationBusy ? null : widget.onDictation,
        ),
        _EditorToolButton(
          tooltip: '撤销',
          icon: Icons.undo_rounded,
          selected: false,
          onPressed: history.canUndo ? editor?.undo : null,
        ),
        _EditorToolButton(
          tooltip: '重做',
          icon: Icons.redo_rounded,
          selected: false,
          onPressed: history.canRedo ? editor?.redo : null,
        ),
        _EditorToolButton(
          tooltip: '加粗',
          icon: Icons.format_bold_rounded,
          selected: format.bold,
          onPressed: editor?.toggleBold,
        ),
        _EditorToolButton(
          tooltip: '下划线',
          icon: Icons.format_underlined_rounded,
          selected: format.underline,
          onPressed: editor?.toggleUnderline,
        ),
        _FontSizeMenuButton(
          value: format.fontSize,
          onSelected: editor?.setFontSize,
        ),
        _EditorToolButton(
          tooltip: '减少缩进',
          icon: Icons.format_indent_decrease_rounded,
          selected: false,
          onPressed: editor == null || format.indent == 0
              ? null
              : () => editor.changeIndent(-1),
        ),
        _EditorToolButton(
          tooltip: '增加缩进',
          icon: Icons.format_indent_increase_rounded,
          selected: false,
          onPressed: editor == null || format.indent == 3
              ? null
              : () => editor.changeIndent(1),
        ),
        _EditorToolButton(
          tooltip: '待办事项',
          icon: Icons.check_box_outlined,
          selected: active == NoteBlockType.todo,
          onPressed: () => editor?.toggleBlock(NoteBlockType.todo),
        ),
        _EditorToolButton(
          tooltip: '无序列表',
          icon: Icons.format_list_bulleted_rounded,
          selected: active == NoteBlockType.bullet,
          onPressed: () => editor?.toggleBlock(NoteBlockType.bullet),
        ),
        _EditorToolButton(
          tooltip: '有序列表',
          icon: Icons.format_list_numbered_rounded,
          selected: active == NoteBlockType.ordered,
          onPressed: () => editor?.toggleBlock(NoteBlockType.ordered),
        ),
        _EditorToolButton(
          tooltip: '引用',
          icon: Icons.format_quote_rounded,
          selected: active == NoteBlockType.quote,
          onPressed: () => editor?.toggleBlock(NoteBlockType.quote),
        ),
        _EditorToolButton(
          tooltip: '分割线',
          icon: Icons.horizontal_rule_rounded,
          selected: active == NoteBlockType.divider,
          onPressed: editor?.insertDivider ?? () {},
        ),
        _EditorToolButton(
          tooltip: '引用附件',
          icon: Icons.add_link_rounded,
          selected: active == NoteBlockType.attachment,
          onPressed: widget.onReferenceAttachment,
        ),
      ],
    );
  }
}

class _LiveDictationBar extends StatelessWidget {
  final RealtimeDictationService service;
  final VoidCallback onCancel;
  final VoidCallback? onFinish;
  final VoidCallback? onShowDiagnostics;

  const _LiveDictationBar({
    required this.service,
    required this.onCancel,
    required this.onFinish,
    required this.onShowDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = service.elapsed.inSeconds;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final label = switch (service.status) {
      RealtimeDictationStatus.preparing => '正在加载本地模型…',
      RealtimeDictationStatus.stopping => '正在整理最后一句…',
      RealtimeDictationStatus.failed => service.errorMessage ?? '实时听写失败',
      _ => service.partialText.isEmpty ? '正在聆听…' : service.partialText,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _InputLevel(level: service.inputLevel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.status == RealtimeDictationStatus.listening
                      ? '实时听写  $time'
                      : '本地语音输入',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.coral,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (onShowDiagnostics != null)
            IconButton(
              tooltip: '实时听写诊断',
              onPressed: onShowDiagnostics,
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          IconButton(
            tooltip: '取消听写',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
          if (onFinish != null)
            FilledButton(
              onPressed: onFinish,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 38),
              ),
              child: const Text('完成'),
            ),
        ],
      ),
    );
  }
}

class _DictationDiagnosticsOverlay extends StatefulWidget {
  final RealtimeDictationService service;
  final bool collapsed;
  final double height;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onClose;

  const _DictationDiagnosticsOverlay({
    required this.service,
    required this.collapsed,
    required this.height,
    required this.onMove,
    required this.onResize,
    required this.onToggleCollapsed,
    required this.onClose,
  });

  @override
  State<_DictationDiagnosticsOverlay> createState() =>
      _DictationDiagnosticsOverlayState();
}

class _DictationDiagnosticsOverlayState
    extends State<_DictationDiagnosticsOverlay> {
  final _scrollController = ScrollController();

  RealtimeDictationService get service => widget.service;
  bool get collapsed => widget.collapsed;
  double get height => widget.height;
  ValueChanged<Offset> get onMove => widget.onMove;
  ValueChanged<Offset> get onResize => widget.onResize;
  VoidCallback get onToggleCollapsed => widget.onToggleCollapsed;
  VoidCallback get onClose => widget.onClose;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followLatestIfNeeded() {
    final shouldFollow =
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter < 32;
    if (!shouldFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('dictation-debug-overlay'),
    color: const Color(0xEE181818),
    elevation: 12,
    shadowColor: Colors.black54,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!collapsed) _followLatestIfNeeded();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onMove(details.delta),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '实时听写诊断 · Debug only',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: collapsed ? '展开' : '折叠',
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleCollapsed,
                      icon: Icon(
                        collapsed
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        size: 19,
                        color: Colors.white70,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭诊断窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              const Divider(height: 1, color: Colors.white12),
              SizedBox(
                height: (height - 116).clamp(100.0, 520.0),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                    child: SelectableText(
                      service.debugReport,
                      style: const TextStyle(
                        color: Color(0xFFD8F8D2),
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: service.clearDebugDiagnostics,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('export-dictation-debug-audio'),
                      onPressed: service.debugAudioAvailable
                          ? () async {
                              final file = await service
                                  .createDebugAudioExport();
                              if (file == null) return;
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [
                                    XFile(
                                      file.path,
                                      mimeType: 'audio/wav',
                                      name: file.uri.pathSegments.last,
                                    ),
                                  ],
                                  title: 'FKNotes 实时听写诊断录音',
                                  subject: '模型实际收到的 PCM16 音频',
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.audio_file_outlined, size: 17),
                      label: const Text('导出录音'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      key: const Key('copy-dictation-debug-report'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: service.debugReport),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('诊断信息已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 17),
                      label: const Text('复制全部'),
                    ),
                    const SizedBox(width: 4),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        key: const Key('resize-dictation-debug-overlay'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) => onResize(details.delta),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 17,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _InputLevel extends StatelessWidget {
  final double level;
  const _InputLevel({required this.level});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 28,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var index = 0; index < 4; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 6 + 20 * (level * (1 + index * .18)).clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    ),
  );
}

class _EditorToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  const _EditorToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: selected ? AppColors.softGreen : Colors.transparent,
      foregroundColor: selected ? AppColors.coral : AppColors.muted,
    ),
    icon: Icon(icon),
  );
}

class _FontSizeMenuButton extends StatelessWidget {
  final double? value;
  final ValueChanged<double>? onSelected;

  const _FontSizeMenuButton({required this.value, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const sizes = [14.0, 17.0, 20.0, 24.0, 28.0];
    return PopupMenuButton<double>(
      tooltip: '字号',
      enabled: onSelected != null,
      initialValue: value,
      onSelected: onSelected,
      position: PopupMenuPosition.over,
      itemBuilder: (context) => [
        for (final size in sizes)
          PopupMenuItem(
            value: size,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${size.toInt()}',
                    style: TextStyle(
                      color: value == size ? AppColors.coral : AppColors.ink,
                      fontWeight: value == size
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  size == 17 ? '正文' : '号字',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const Spacer(),
                if (value == size)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.coral,
                  ),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 48,
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value?.toInt().toString() ?? '—',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddContentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddContentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.softAmber,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.moss),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _AttachmentImportTile extends StatelessWidget {
  final AttachmentImportJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _AttachmentImportTile({
    required this.job,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final progress = job.progress;
    final color = NoteCard.colorForType(job.type);
    final statusText = switch (job.status) {
      AttachmentImportStatus.importing =>
        job.type == NoteType.image && progress == 1
            ? '正在生成缩略图…'
            : progress == null
            ? '正在导入 · ${_formatBytes(job.copiedBytes)}'
            : '正在导入 ${(progress * 100).round()}% · '
                  '${_formatBytes(job.copiedBytes)} / ${_formatBytes(job.totalBytes)}',
      AttachmentImportStatus.completed => '导入完成，正在保存到笔记…',
      AttachmentImportStatus.failed =>
        job.errorMessage?.trim().isNotEmpty == true
            ? '导入失败 · ${job.errorMessage}'
            : '导入失败，请重试',
      AttachmentImportStatus.canceled => '导入已取消',
    };
    return Material(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(NoteCard.iconForType(job.type), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: job.status == AttachmentImportStatus.failed
                          ? color
                          : AppColors.muted,
                    ),
                  ),
                  if (job.status == AttachmentImportStatus.importing ||
                      job.status == AttachmentImportStatus.completed) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: job.status == AttachmentImportStatus.completed
                            ? 1
                            : progress,
                        minHeight: 4,
                        backgroundColor: AppColors.line,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (job.status == AttachmentImportStatus.importing)
              IconButton(
                tooltip: '取消导入',
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              )
            else if (job.status == AttachmentImportStatus.failed) ...[
              IconButton(
                tooltip: '重新选择${job.type.label}',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: '移除',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class _AttachmentEditorTile extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onReference;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  const _AttachmentEditorTile({
    required this.attachment,
    required this.onOpen,
    required this.onReference,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = NoteCard.colorForType(attachment.type);
    final thumbnailPath = attachment.thumbnailPath;
    final thumbnail = thumbnailPath == null
        ? null
        : File(FileStorageService.instance.absolutePath(thumbnailPath));
    return Material(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumbnail?.existsSync() == true
                    ? Image.file(
                        thumbnail!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 54,
                        height: 54,
                        color: color.withValues(alpha: .1),
                        child: Icon(
                          NoteCard.iconForType(attachment.type),
                          color: color,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${attachment.type.label} · ${_formatSize(attachment.fileSize)}${attachment.ocrText?.trim().isNotEmpty == true ? ' · OCR' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '调整附件',
                onSelected: (value) {
                  switch (value) {
                    case 'up':
                      onMoveUp();
                    case 'down':
                      onMoveDown();
                    case 'reference':
                      onReference();
                    case 'remove':
                      onRemove();
                  }
                },
                itemBuilder: (_) => [
                  AppPopupMenuItem.action(
                    value: 'up',
                    enabled: canMoveUp,
                    icon: Icons.arrow_upward_rounded,
                    label: '上移',
                  ),
                  AppPopupMenuItem.action(
                    value: 'down',
                    enabled: canMoveDown,
                    icon: Icons.arrow_downward_rounded,
                    label: '下移',
                  ),
                  AppPopupMenuItem.action(
                    value: 'reference',
                    icon: Icons.add_link_rounded,
                    label: '引用到正文',
                  ),
                  AppPopupMenuItem.action(
                    value: 'remove',
                    icon: Icons.remove_circle_outline_rounded,
                    label: '移除',
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}
