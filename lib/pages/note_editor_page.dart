import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_block_editor.dart';
import '../widgets/note_card.dart';
import 'media_detail_page.dart';
import 'record_audio_page.dart';

class NoteEditorPage extends StatefulWidget {
  final NoteEntry? existingEntry;

  const NoteEditorPage({super.key, this.existingEntry});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late String _lastTitleText;
  late String _lastContentText;
  final _blockEditorKey = GlobalKey<NoteBlockEditorState>();
  late List<String> _tags;
  late bool _favorite;
  late bool _pinned;
  late List<NoteAttachment> _attachments;
  final List<NoteAttachment> _removedAttachments = [];
  final _picker = ImagePicker();
  final _storage = FileStorageService.instance;
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
    _title = TextEditingController(text: entry?.title ?? '');
    _content = TextEditingController(text: entry?.content ?? '');
    _lastTitleText = _title.text;
    _lastContentText = _content.text;
    _tags = [...?entry?.tags];
    _favorite = entry?.isFavorite ?? false;
    _pinned = entry?.isPinned ?? false;
    _attachments = [...?entry?.allAttachments];
    _title.addListener(_onTitleChanged);
    _content.addListener(_onContentChanged);
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
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<bool> _persist() async {
    if (_saving) {
      _saveAgain = true;
      return false;
    }
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty && content.isEmpty && _attachments.isEmpty) {
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

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;
    await _importFiles(images, NoteType.image);
  }

  Future<void> _takePhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (image != null) {
      await _importFiles([image], NoteType.image);
    }
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) await _importFiles([video], NoteType.video);
  }

  Future<void> _pickAudio() async {
    const group = XTypeGroup(label: 'Audio', mimeTypes: ['audio/*']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null) await _importFiles([file], NoteType.audio);
  }

  Future<void> _pickDocument() async {
    const group = XTypeGroup(
      label: 'Files',
      extensions: [
        'pdf',
        'txt',
        'md',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
      ],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null) await _importFiles([file], NoteType.document);
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

  Future<void> _importFiles(List<XFile> files, NoteType type) async {
    if (_importing) return;
    setState(() => _importing = true);
    final imported = <NoteAttachment>[];
    try {
      for (final selected in files) {
        final source = File(selected.path);
        final folder = switch (type) {
          NoteType.image => 'images',
          NoteType.audio => 'audio',
          NoteType.video => 'video',
          NoteType.document => 'documents',
          NoteType.text => 'documents',
        };
        final storedPath = await _storage.copyFile(source, folder);
        String? thumbnailPath;
        if (type == NoteType.image) {
          final thumbnail = await _storage.generateThumbnail(storedPath);
          thumbnailPath = thumbnail.isEmpty ? null : thumbnail;
        }
        imported.add(
          NoteAttachment(
            type: type,
            filePath: storedPath,
            fileName: selected.name,
            fileSize: await _storage.getFileSize(storedPath),
            mimeType:
                lookupMimeType(selected.path) ??
                (type == NoteType.document
                    ? 'application/octet-stream'
                    : '${type.name}/*'),
            thumbnailPath: thumbnailPath,
            createdAt: DateTime.now(),
          ),
        );
      }
      _addAttachments(imported);
    } catch (error) {
      for (final attachment in imported) {
        await _storage.deleteFile(attachment.filePath);
        await _storage.deleteFile(attachment.thumbnailPath);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('添加失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
    final type = _attachments.isEmpty ? NoteType.text : _attachments.first.type;
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
                  Text(
                    _saving
                        ? '正在保存…'
                        : _changed
                        ? '本地草稿'
                        : '已保存在本机',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
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
                      if (_attachments.isNotEmpty) ...[
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
                              '${_attachments.length} 项附件',
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
                          index < _attachments.length;
                          index++
                        ) ...[
                          _AttachmentEditorTile(
                            attachment: _attachments[index],
                            onOpen: () => _openAttachment(_attachments[index]),
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
                        attachments: _attachments,
                        onOpenAttachment: _openAttachment,
                        minLines: _attachments.isEmpty ? 16 : 10,
                        hintText: _attachments.isNotEmpty
                            ? '添加说明、想法或摘要…'
                            : '开始记录…',
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Row(
                  children: [
                    IconButton.filled(
                      tooltip: '添加图片、录音或文件',
                      onPressed: _importing ? null : _showAddContentSheet,
                      icon: _importing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: TextFieldTapRegion(
                          child: _EditorToolbar(
                            editorKey: _blockEditorKey,
                            onReferenceAttachment:
                                _showAttachmentReferenceSheet,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _content,
                      builder: (_, value, child) => Text(
                        '${NoteBlockCodec.visibleCharacterCount(value.text)} 字',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
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

  const _EditorToolbar({
    required this.editorKey,
    required this.onReferenceAttachment,
  });

  @override
  State<_EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<_EditorToolbar> {
  ValueNotifier<NoteBlockType>? _activeType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = widget.editorKey.currentState?.activeType;
      if (identical(notifier, _activeType)) return;
      _activeType?.removeListener(_refresh);
      _activeType = notifier?..addListener(_refresh);
      _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _activeType?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeType?.value ?? NoteBlockType.paragraph;
    final editor = widget.editorKey.currentState;
    return Row(
      children: [
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
          tooltip: '引用附件',
          icon: Icons.add_link_rounded,
          selected: active == NoteBlockType.attachment,
          onPressed: widget.onReferenceAttachment,
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
      ],
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

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
