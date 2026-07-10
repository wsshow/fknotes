import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/video_import_service.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_block_editor.dart';
import '../widgets/note_card.dart';
import 'media_detail_page.dart';
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

class _NoteEditorPageState extends State<NoteEditorPage> {
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
  late final Set<String> _importJobIds;
  NoteProvider? _provider;
  NoteEntry? _entry;
  Timer? _autosave;
  bool _changed = false;
  bool _saving = false;
  bool _saveAgain = false;
  bool _importing = false;

  bool get _isEditing => _entry != null;

  @override
  void initState() {
    super.initState();
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
    _provider?.removeListener(_handleProviderChanged);
    _title.dispose();
    _content.dispose();
    super.dispose();
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
    final controller = TextEditingController(text: _tags.join(', '));
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：工作, 灵感, 稍后阅读'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text
                  .split(RegExp('[,，]'))
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .take(8)
                  .toList(),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tags != null) {
      setState(() {
        _tags = tags;
        _changed = true;
      });
      _scheduleAutosave();
    }
  }

  @override
  Widget build(BuildContext context) {
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
              tooltip: _favorite ? '取消收藏' : '收藏',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _favorite = !_favorite;
                  _changed = true;
                });
                _scheduleAutosave();
              },
              icon: Icon(
                _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _favorite ? const Color(0xFFE3A82B) : null,
              ),
            ),
            IconButton(
              tooltip: _pinned ? '取消置顶' : '置顶',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _pinned = !_pinned;
                  _changed = true;
                });
                _scheduleAutosave();
              },
              icon: Icon(
                Icons.vertical_align_top_rounded,
                size: 24,
                color: _pinned ? AppColors.moss : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
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
                          textCapitalization: TextCapitalization.sentences,
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
                              avatar: const Icon(Icons.add_rounded, size: 17),
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
                              onCancel: () =>
                                  _removeAttachmentImport(importJobs[index]),
                              onRetry: () =>
                                  _retryAttachmentImport(importJobs[index]),
                              onRemove: () =>
                                  _removeAttachmentImport(importJobs[index]),
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
                              onReference: () => _blockEditorKey.currentState
                                  ?.insertAttachmentReference(
                                    _attachments[index].filePath,
                                  ),
                              canMoveUp: index > 0,
                              canMoveDown: index < _attachments.length - 1,
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
                  child: Row(
                    children: [
                      IconButton.filled(
                        tooltip: '添加图片、录音或文件',
                        onPressed: _importing ? null : _showAddContentSheet,
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
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

class _EditorToolbar extends StatefulWidget {
  final GlobalKey<NoteBlockEditorState> editorKey;
  final VoidCallback onReferenceAttachment;

  const _EditorToolbar({
    required this.editorKey,
    required this.onReferenceAttachment,
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
    return Row(
      children: [
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
