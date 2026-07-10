import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../services/file_storage_service.dart';
import 'editor_context_menu.dart';
import 'note_card.dart';

enum NoteBlockType {
  paragraph,
  bullet,
  ordered,
  todo,
  quote,
  divider,
  attachment,
}

class NoteBlockData {
  final NoteBlockType type;
  final String text;
  final bool checked;
  final String? attachmentPath;

  const NoteBlockData(
    this.type,
    this.text, {
    this.checked = false,
    this.attachmentPath,
  });
}

/// Keeps the visual document readable by search, export and other text apps.
class NoteBlockCodec {
  static final _divider = RegExp(r'^\s*(?:---|___|\*\*\*|─{3,})\s*$');
  static final _todo = RegExp(r'^\s*(☐|☑|\[[ xX]\])(?:\s+(.*))?\s*$');
  static final _ordered = RegExp(r'^\s*\d+[.)、](?:\s+(.*))?\s*$');
  static final _bullet = RegExp(r'^\s*[•*-](?:\s+(.*))?\s*$');
  static final _quote = RegExp(r'^\s*>(?:\s?(.*))?\s*$');
  static final _attachment = RegExp(r'^\[\[附件:(.+)\]\]$');

  static List<NoteBlockData> decode(String source) {
    if (source.isEmpty) {
      return const [NoteBlockData(NoteBlockType.paragraph, '')];
    }
    final parsed = source.replaceAll('\r\n', '\n').split('\n').map((line) {
      final attachment = _attachment.firstMatch(line);
      if (attachment != null) {
        return NoteBlockData(
          NoteBlockType.attachment,
          '',
          attachmentPath: attachment.group(1),
        );
      }
      if (_divider.hasMatch(line)) {
        return const NoteBlockData(NoteBlockType.divider, '');
      }
      final todo = _todo.firstMatch(line);
      if (todo != null) {
        final marker = todo.group(1)!;
        return NoteBlockData(
          NoteBlockType.todo,
          todo.group(2) ?? '',
          checked: marker == '☑' || marker.toLowerCase() == '[x]',
        );
      }
      final ordered = _ordered.firstMatch(line);
      if (ordered != null) {
        return NoteBlockData(NoteBlockType.ordered, ordered.group(1) ?? '');
      }
      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        return NoteBlockData(NoteBlockType.bullet, bullet.group(1) ?? '');
      }
      final quote = _quote.firstMatch(line);
      if (quote != null) {
        return NoteBlockData(NoteBlockType.quote, quote.group(1) ?? '');
      }
      return NoteBlockData(NoteBlockType.paragraph, line);
    }).toList();
    // A divider owns its vertical rhythm, so redundant blank blocks directly
    // beside it are omitted from the visual document.
    return [
      for (var index = 0; index < parsed.length; index++)
        if (!(parsed[index].type == NoteBlockType.paragraph &&
            parsed[index].text.isEmpty &&
            ((index > 0 && parsed[index - 1].type == NoteBlockType.divider) ||
                (index + 1 < parsed.length &&
                    parsed[index + 1].type == NoteBlockType.divider))))
          parsed[index],
    ];
  }

  static int visibleCharacterCount(String source) =>
      decode(source).fold(0, (count, block) => count + block.text.runes.length);

  static String encode(List<NoteBlockData> blocks) {
    var orderedNumber = 0;
    NoteBlockType? previous;
    final lines = <String>[];
    for (final block in blocks) {
      if (block.type == NoteBlockType.ordered) {
        orderedNumber = previous == NoteBlockType.ordered
            ? orderedNumber + 1
            : 1;
      } else {
        orderedNumber = 0;
      }
      lines.add(switch (block.type) {
        NoteBlockType.paragraph => block.text,
        NoteBlockType.bullet => '• ${block.text}',
        NoteBlockType.ordered => '$orderedNumber. ${block.text}',
        NoteBlockType.todo => '${block.checked ? '☑' : '☐'} ${block.text}',
        NoteBlockType.quote => '> ${block.text}',
        NoteBlockType.divider => '---',
        NoteBlockType.attachment => '[[附件:${block.attachmentPath ?? ''}]]',
      });
      previous = block.type;
    }
    return lines.join('\n');
  }
}

class NoteBlockEditor extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int minLines;
  final List<NoteAttachment> attachments;
  final ValueChanged<NoteAttachment>? onOpenAttachment;

  const NoteBlockEditor({
    super.key,
    required this.controller,
    required this.hintText,
    this.minLines = 10,
    this.attachments = const [],
    this.onOpenAttachment,
  });

  @override
  NoteBlockEditorState createState() => NoteBlockEditorState();
}

class NoteBlockEditorState extends State<NoteBlockEditor> {
  final ValueNotifier<NoteBlockType> activeType = ValueNotifier(
    NoteBlockType.paragraph,
  );
  late final List<_EditableBlock> _blocks;
  int _activeIndex = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _blocks = NoteBlockCodec.decode(
      widget.controller.text,
    ).map(_makeBlock).toList();
  }

  _EditableBlock _makeBlock(NoteBlockData data) {
    late final _EditableBlock block;
    block = _EditableBlock(
      type: data.type,
      checked: data.checked,
      attachmentPath: data.attachmentPath,
      controller: _BlockTextEditingController(text: data.text),
      focusNode: FocusNode(),
    );
    block.controller.addListener(_syncDocument);
    block.focusNode.addListener(() {
      if (!block.focusNode.hasFocus || !mounted) return;
      final index = _blocks.indexOf(block);
      if (index >= 0) {
        _activeIndex = index;
        activeType.value = block.type;
      }
    });
    return block;
  }

  List<NoteBlockData> get _document => [
    for (final block in _blocks)
      NoteBlockData(
        block.type,
        block.controller.visibleTextValue,
        checked: block.checked,
        attachmentPath: block.attachmentPath,
      ),
  ];

  void _syncDocument() {
    if (_syncing) return;
    final text = NoteBlockCodec.encode(_document);
    if (widget.controller.text == text) return;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void toggleBlock(NoteBlockType type) {
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final block = _blocks[_activeIndex];
    if (block.type == NoteBlockType.divider ||
        block.type == NoteBlockType.attachment) {
      _insertAfterDivider(type);
      return;
    }
    final selection = block.controller.visibleSelectionValue;
    setState(() {
      block.type = block.type == type ? NoteBlockType.paragraph : type;
      if (block.type != NoteBlockType.todo) block.checked = false;
      activeType.value = block.type;
    });
    _syncDocument();
    _refocus(block, selection: selection);
  }

  void insertDivider() {
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final current = _blocks[_activeIndex];
    if (current.type == NoteBlockType.divider) {
      _insertAfterDivider(NoteBlockType.paragraph);
      return;
    }
    final selection = current.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start
        : current.controller.visibleTextValue.length;
    final end = selection.isValid ? selection.end : start;
    final before = current.controller.visibleTextValue.substring(0, start);
    final after = current.controller.visibleTextValue.substring(end);
    final divider = _makeBlock(const NoteBlockData(NoteBlockType.divider, ''));
    final next = _makeBlock(NoteBlockData(NoteBlockType.paragraph, after));
    _syncing = true;
    current.controller.visibleTextValue = before;
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, divider);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
  }

  void insertAttachmentReference(String filePath) {
    HapticFeedback.selectionClick();
    if (_activeIndex >= _blocks.length) _activeIndex = _blocks.length - 1;
    final current = _blocks[_activeIndex];
    final reference = _makeBlock(
      NoteBlockData(NoteBlockType.attachment, '', attachmentPath: filePath),
    );
    if (current.type == NoteBlockType.divider ||
        current.type == NoteBlockType.attachment) {
      final next = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      setState(() {
        _blocks.insert(_activeIndex + 1, reference);
        _blocks.insert(_activeIndex + 2, next);
        _activeIndex += 2;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(next, atStart: true);
      return;
    }

    final selection = current.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start
        : current.controller.visibleTextValue.length;
    final end = selection.isValid ? selection.end : start;
    final before = current.controller.visibleTextValue.substring(0, start);
    final after = current.controller.visibleTextValue.substring(end);
    final next = _makeBlock(NoteBlockData(NoteBlockType.paragraph, after));
    _syncing = true;
    current.controller.visibleTextValue = before;
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, reference);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
  }

  void _insertAfterDivider(NoteBlockType type) {
    final next = _makeBlock(NoteBlockData(type, ''));
    setState(() {
      _blocks.insert(_activeIndex + 1, next);
      _activeIndex++;
      activeType.value = type;
    });
    _syncDocument();
    _refocus(next, atStart: true);
  }

  void _splitBlock(_EditableBlock block, TextSelection replacedSelection) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    final text = block.controller.visibleTextValue;
    final start = replacedSelection.start.clamp(0, text.length);
    final end = replacedSelection.end.clamp(start, text.length);
    final before = text.substring(0, start);
    final after = text.substring(end);

    if (block.type != NoteBlockType.paragraph &&
        before.trim().isEmpty &&
        after.trim().isEmpty) {
      setState(() {
        block.type = NoteBlockType.paragraph;
        block.checked = false;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }

    final nextType = switch (block.type) {
      NoteBlockType.bullet => NoteBlockType.bullet,
      NoteBlockType.ordered => NoteBlockType.ordered,
      NoteBlockType.todo => NoteBlockType.todo,
      NoteBlockType.quote => NoteBlockType.quote,
      _ => NoteBlockType.paragraph,
    };
    final next = _makeBlock(NoteBlockData(nextType, after));
    _syncing = true;
    block.controller.value = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    _syncing = false;
    setState(() {
      _blocks.insert(index + 1, next);
      _activeIndex = index + 1;
      activeType.value = nextType;
    });
    _syncDocument();
    _refocus(next, atStart: true);
  }

  void _mergeWithPrevious(_EditableBlock block) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index <= 0) return;
    final previous = _blocks[index - 1];
    if (previous.type == NoteBlockType.divider) {
      setState(() => _blocks.removeAt(index - 1).dispose());
      _activeIndex = index - 1;
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }
    if (previous.type == NoteBlockType.attachment) {
      setState(() => _blocks.removeAt(index - 1).dispose());
      _activeIndex = index - 1;
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }
    final joinAt = previous.controller.visibleTextValue.length;
    _syncing = true;
    previous.controller.visibleTextValue += block.controller.visibleTextValue;
    _syncing = false;
    setState(() {
      _blocks.removeAt(index).dispose();
      _activeIndex = index - 1;
      activeType.value = previous.type;
    });
    _syncDocument();
    _refocus(previous, offset: joinAt);
  }

  void _backspaceAtStart(_EditableBlock block) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index < 0) return;

    if (block.type != NoteBlockType.paragraph) {
      setState(() {
        block.type = NoteBlockType.paragraph;
        block.checked = false;
        _activeIndex = index;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(block, atStart: true);
      return;
    }

    _mergeWithPrevious(block);
  }

  KeyEventResult _handleBlockKeyEvent(_EditableBlock block, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final selection = block.controller.visibleSelectionValue;
    if (!selection.isValid || !selection.isCollapsed || selection.start != 0) {
      return KeyEventResult.ignored;
    }
    _backspaceAtStart(block);
    return KeyEventResult.handled;
  }

  void _refocus(
    _EditableBlock block, {
    bool atStart = false,
    int? offset,
    TextSelection? selection,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      block.focusNode.requestFocus();
      if (selection?.isValid == true) {
        block.controller.visibleSelectionValue = selection!;
      } else {
        final target =
            offset ?? (atStart ? 0 : block.controller.visibleTextValue.length);
        block.controller.visibleSelectionValue = TextSelection.collapsed(
          offset: target,
        );
      }
    });
  }

  int _numberFor(int index) {
    var number = 1;
    for (var i = index - 1; i >= 0; i--) {
      if (_blocks[i].type != NoteBlockType.ordered) break;
      number++;
    }
    return number;
  }

  @override
  void dispose() {
    activeType.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final editable = _blocks.where(
          (item) =>
              item.type != NoteBlockType.divider &&
              item.type != NoteBlockType.attachment,
        );
        if (editable.isNotEmpty) _refocus(editable.last);
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minLines * 27),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < _blocks.length; index++)
              _buildBlock(index),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(int index) {
    final block = _blocks[index];
    if (block.type == NoteBlockType.attachment) {
      return _buildAttachmentReference(index, block);
    }
    if (block.type == NoteBlockType.divider) {
      return Semantics(
        label: '分割线',
        child: InkWell(
          onTap: () {
            _activeIndex = index;
            activeType.value = NoteBlockType.divider;
            FocusScope.of(context).unfocus();
          },
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 17),
            child: Divider(color: AppColors.line, thickness: 1),
          ),
        ),
      );
    }

    final quote = block.type == NoteBlockType.quote;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: quote ? const EdgeInsets.only(left: 10) : EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: quote ? AppColors.coral : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: block.type == NoteBlockType.paragraph || quote ? 0 : 34,
            height: 43,
            child: _buildLeading(index, block),
          ),
          Expanded(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) => _handleBlockKeyEvent(block, event),
              child: Stack(
                children: [
                  TextField(
                    controller: block.controller,
                    focusNode: block.focusNode,
                    contextMenuBuilder: buildEditorContextMenu,
                    inputFormatters: [
                      _BlockInputFormatter(
                        onNewline: (selection) => _splitBlock(block, selection),
                        onBackspaceAtStart: () => _backspaceAtStart(block),
                      ),
                    ],
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: AppColors.coral,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.62,
                      color: quote ? AppColors.muted : AppColors.ink,
                      fontStyle: quote ? FontStyle.italic : FontStyle.normal,
                      decoration:
                          block.type == NoteBlockType.todo && block.checked
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.muted,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
                    ),
                  ),
                  if (index == 0)
                    Positioned(
                      left: 0,
                      top: 7,
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: block.controller,
                        builder: (context, value, child) => IgnorePointer(
                          child: block.controller.visibleTextValue.isEmpty
                              ? Text(
                                  widget.hintText,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 17,
                                    height: 1.62,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentReference(int index, _EditableBlock block) {
    NoteAttachment? attachment;
    for (final item in widget.attachments) {
      if (item.filePath == block.attachmentPath) {
        attachment = item;
        break;
      }
    }
    final resolved = attachment;
    final color = resolved == null
        ? AppColors.muted
        : NoteCard.colorForType(resolved.type);
    final thumbnailPath = resolved?.thumbnailPath;
    final thumbnail = thumbnailPath == null
        ? null
        : File(FileStorageService.instance.absolutePath(thumbnailPath));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Material(
        color: resolved == null
            ? AppColors.softBlue
            : color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: resolved == null
              ? null
              : () => widget.onOpenAttachment?.call(resolved),
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
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 46,
                          height: 46,
                          color: color.withValues(alpha: .1),
                          child: Icon(
                            resolved == null
                                ? Icons.link_off_rounded
                                : NoteCard.iconForType(resolved.type),
                            size: 22,
                            color: color,
                          ),
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolved?.fileName ?? '附件已移除',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        resolved == null
                            ? '这个引用已失效，可以移除引用'
                            : '${resolved.type.label} · ${_formatSize(resolved.fileSize)} · 点击预览',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '移除引用',
                  onPressed: () => _removeAtomicBlock(index),
                  icon: const Icon(Icons.close_rounded, size: 19),
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _removeAtomicBlock(int index) {
    HapticFeedback.selectionClick();
    final removed = _blocks.removeAt(index)..dispose();
    assert(removed.type == NoteBlockType.attachment);
    _EditableBlock target;
    if (_blocks.isEmpty) {
      target = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      _blocks.add(target);
      _activeIndex = 0;
    } else if (index < _blocks.length &&
        _blocks[index].type != NoteBlockType.divider &&
        _blocks[index].type != NoteBlockType.attachment) {
      target = _blocks[index];
      _activeIndex = index;
    } else {
      target = _makeBlock(const NoteBlockData(NoteBlockType.paragraph, ''));
      _blocks.insert(index.clamp(0, _blocks.length), target);
      _activeIndex = index.clamp(0, _blocks.length - 1);
    }
    setState(() => activeType.value = target.type);
    _syncDocument();
    _refocus(target, atStart: true);
  }

  static String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';

  Widget _buildLeading(int index, _EditableBlock block) {
    return switch (block.type) {
      NoteBlockType.bullet => const Center(
        child: Icon(Icons.circle, size: 6, color: AppColors.ink),
      ),
      NoteBlockType.ordered => Center(
        child: Text(
          '${_numberFor(index)}.',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ),
      NoteBlockType.todo => Center(
        child: InkResponse(
          radius: 20,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => block.checked = !block.checked);
            _syncDocument();
          },
          child: Icon(
            block.checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 22,
            color: block.checked ? AppColors.coral : AppColors.muted,
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _BlockTextEditingController extends TextEditingController {
  static const boundary = editorBlockBoundary;

  _BlockTextEditingController({String text = ''})
    : super.fromValue(
        withBoundary(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        ),
      );

  static String visibleText(String rawText) => rawText.startsWith(boundary)
      ? rawText.substring(boundary.length)
      : rawText;

  static TextSelection visibleSelection(TextSelection rawSelection) {
    if (!rawSelection.isValid) return rawSelection;
    return rawSelection.copyWith(
      baseOffset: (rawSelection.baseOffset - boundary.length).clamp(0, 1 << 31),
      extentOffset: (rawSelection.extentOffset - boundary.length).clamp(
        0,
        1 << 31,
      ),
    );
  }

  static TextEditingValue withBoundary(TextEditingValue incoming) {
    final hasBoundary = incoming.text.startsWith(boundary);
    final shift = hasBoundary ? 0 : boundary.length;
    final normalizedText = hasBoundary
        ? incoming.text
        : '$boundary${incoming.text}';

    int shiftedOffset(int value) {
      if (value < 0) return value;
      final shifted = value + shift;
      if (shifted < boundary.length) return boundary.length;
      if (shifted > normalizedText.length) return normalizedText.length;
      return shifted;
    }

    final selection = incoming.selection.isValid
        ? incoming.selection.copyWith(
            baseOffset: shiftedOffset(incoming.selection.baseOffset),
            extentOffset: shiftedOffset(incoming.selection.extentOffset),
          )
        : incoming.selection;
    final composing = incoming.composing.isValid
        ? TextRange(
            start: shiftedOffset(incoming.composing.start),
            end: shiftedOffset(incoming.composing.end),
          )
        : TextRange.empty;
    return incoming.copyWith(
      text: normalizedText,
      selection: selection,
      composing: composing,
    );
  }

  String get visibleTextValue => visibleText(super.text);

  set visibleTextValue(String newText) {
    text = newText;
  }

  TextSelection get visibleSelectionValue => visibleSelection(super.selection);

  set visibleSelectionValue(TextSelection newSelection) {
    if (!newSelection.isValid) {
      super.selection = newSelection;
      return;
    }
    super.selection = newSelection.copyWith(
      baseOffset: newSelection.baseOffset + boundary.length,
      extentOffset: newSelection.extentOffset + boundary.length,
    );
  }

  @override
  set value(TextEditingValue newValue) {
    super.value = withBoundary(newValue);
  }
}

class _EditableBlock {
  NoteBlockType type;
  bool checked;
  final String? attachmentPath;
  final _BlockTextEditingController controller;
  final FocusNode focusNode;

  _EditableBlock({
    required this.type,
    required this.checked,
    this.attachmentPath,
    required this.controller,
    required this.focusNode,
  });

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _BlockInputFormatter extends TextInputFormatter {
  final ValueChanged<TextSelection> onNewline;
  final VoidCallback onBackspaceAtStart;

  const _BlockInputFormatter({
    required this.onNewline,
    required this.onBackspaceAtStart,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final removedBoundary =
        oldValue.text.startsWith(_BlockTextEditingController.boundary) &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.start ==
            _BlockTextEditingController.boundary.length &&
        newValue.text == oldValue.text.substring(1);
    if (removedBoundary) {
      scheduleMicrotask(onBackspaceAtStart);
      return oldValue;
    }

    final normalized = _BlockTextEditingController.withBoundary(newValue);
    final oldText = _BlockTextEditingController.visibleText(oldValue.text);
    final newText = _BlockTextEditingController.visibleText(normalized.text);
    final insertedNewline =
        newText.length >= oldText.length &&
        newText.contains('\n') &&
        !oldText.contains('\n');
    if (insertedNewline) {
      final selection = oldValue.selection.isValid
          ? _BlockTextEditingController.visibleSelection(oldValue.selection)
          : TextSelection.collapsed(offset: oldText.length);
      scheduleMicrotask(() => onNewline(selection));
      return oldValue;
    }
    return normalized;
  }
}
