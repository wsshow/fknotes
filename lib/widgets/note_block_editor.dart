import 'dart:async';
import 'dart:convert';
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
  final int indent;
  final List<NoteTextStyleRange> styles;

  const NoteBlockData(
    this.type,
    this.text, {
    this.checked = false,
    this.attachmentPath,
    this.indent = 0,
    this.styles = const [],
  });
}

class NoteTextAttributes {
  static const defaultFontSize = 17.0;
  static const defaults = NoteTextAttributes();

  final bool bold;
  final bool underline;
  final double fontSize;

  const NoteTextAttributes({
    this.bold = false,
    this.underline = false,
    this.fontSize = defaultFontSize,
  });

  NoteTextAttributes copyWith({
    bool? bold,
    bool? underline,
    double? fontSize,
  }) => NoteTextAttributes(
    bold: bold ?? this.bold,
    underline: underline ?? this.underline,
    fontSize: fontSize ?? this.fontSize,
  );

  Map<String, Object> toMap() => {
    if (bold) 'bold': true,
    if (underline) 'underline': true,
    if (fontSize != defaultFontSize) 'fontSize': fontSize,
  };

  factory NoteTextAttributes.fromMap(Map<String, Object?> map) =>
      NoteTextAttributes(
        bold: map['bold'] == true,
        underline: map['underline'] == true,
        fontSize: ((map['fontSize'] as num?)?.toDouble() ?? defaultFontSize)
            .clamp(12, 36),
      );

  @override
  bool operator ==(Object other) =>
      other is NoteTextAttributes &&
      bold == other.bold &&
      underline == other.underline &&
      fontSize == other.fontSize;

  @override
  int get hashCode => Object.hash(bold, underline, fontSize);
}

class NoteTextStyleRange {
  final int start;
  final int end;
  final NoteTextAttributes attributes;

  const NoteTextStyleRange(this.start, this.end, this.attributes);

  Map<String, Object> toMap() => {
    'start': start,
    'end': end,
    ...attributes.toMap(),
  };

  factory NoteTextStyleRange.fromMap(Map<String, Object?> map) =>
      NoteTextStyleRange(
        map['start'] as int? ?? 0,
        map['end'] as int? ?? 0,
        NoteTextAttributes.fromMap(map),
      );
}

class NoteEditorFormatState {
  final bool bold;
  final bool underline;
  final double? fontSize;
  final int indent;

  const NoteEditorFormatState({
    this.bold = false,
    this.underline = false,
    this.fontSize = NoteTextAttributes.defaultFontSize,
    this.indent = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is NoteEditorFormatState &&
      bold == other.bold &&
      underline == other.underline &&
      fontSize == other.fontSize &&
      indent == other.indent;

  @override
  int get hashCode => Object.hash(bold, underline, fontSize, indent);
}

class NoteHistoryState {
  final bool canUndo;
  final bool canRedo;

  const NoteHistoryState({this.canUndo = false, this.canRedo = false});

  @override
  bool operator ==(Object other) =>
      other is NoteHistoryState &&
      canUndo == other.canUndo &&
      canRedo == other.canRedo;

  @override
  int get hashCode => Object.hash(canUndo, canRedo);
}

class _EditorSnapshot {
  final String richDocument;
  final int activeIndex;
  final TextSelection selection;

  const _EditorSnapshot({
    required this.richDocument,
    required this.activeIndex,
    required this.selection,
  });
}

class NoteRichDocumentCodec {
  static const version = 1;

  static String encode(List<NoteBlockData> blocks) => jsonEncode({
    'version': version,
    'blocks': [
      for (final block in blocks)
        {
          'type': block.type.name,
          'text': block.text,
          if (block.checked) 'checked': true,
          if (block.attachmentPath != null)
            'attachmentPath': block.attachmentPath,
          if (block.indent > 0) 'indent': block.indent,
          if (block.styles.isNotEmpty)
            'styles': block.styles.map((range) => range.toMap()).toList(),
        },
    ],
  });

  static List<NoteBlockData>? tryDecode(String? source) {
    if (source?.trim().isEmpty ?? true) return null;
    try {
      final root = jsonDecode(source!) as Map<String, Object?>;
      if (root['version'] != version) return null;
      final rawBlocks = root['blocks'] as List<Object?>?;
      if (rawBlocks == null || rawBlocks.isEmpty) return null;
      return rawBlocks.map((raw) {
        final map = raw as Map<String, Object?>;
        final typeName = map['type'] as String? ?? 'paragraph';
        final type = NoteBlockType.values.firstWhere(
          (candidate) => candidate.name == typeName,
          orElse: () => NoteBlockType.paragraph,
        );
        final text = map['text'] as String? ?? '';
        final ranges = <NoteTextStyleRange>[];
        for (final rawRange in map['styles'] as List<Object?>? ?? const []) {
          final range = NoteTextStyleRange.fromMap(
            rawRange as Map<String, Object?>,
          );
          final start = range.start.clamp(0, text.length);
          final end = range.end.clamp(start, text.length);
          if (start < end) {
            ranges.add(NoteTextStyleRange(start, end, range.attributes));
          }
        }
        return NoteBlockData(
          type,
          text,
          checked: map['checked'] == true,
          attachmentPath: map['attachmentPath'] as String?,
          indent: (map['indent'] as int? ?? 0).clamp(0, 3),
          styles: ranges,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }
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
  final String? initialRichContent;
  final ValueChanged<String>? onRichContentChanged;
  final String hintText;
  final int minLines;
  final List<NoteAttachment> attachments;
  final ValueChanged<NoteAttachment>? onOpenAttachment;

  const NoteBlockEditor({
    super.key,
    required this.controller,
    this.initialRichContent,
    this.onRichContentChanged,
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
  final ValueNotifier<NoteEditorFormatState> activeFormat = ValueNotifier(
    const NoteEditorFormatState(),
  );
  final ValueNotifier<NoteHistoryState> historyState = ValueNotifier(
    const NoteHistoryState(),
  );
  late final List<_EditableBlock> _blocks;
  late String _lastRichDocument;
  late _EditorSnapshot _currentSnapshot;
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];
  Timer? _historyGroupTimer;
  bool _historyGroupOpen = false;
  bool _restoringHistory = false;
  int _activeIndex = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final richBlocks = NoteRichDocumentCodec.tryDecode(
      widget.initialRichContent,
    );
    final plainBlocks = NoteBlockCodec.decode(widget.controller.text);
    final blocks =
        richBlocks != null &&
            NoteBlockCodec.encode(richBlocks) == widget.controller.text
        ? richBlocks
        : plainBlocks;
    _blocks = blocks.map(_makeBlock).toList();
    _lastRichDocument = NoteRichDocumentCodec.encode(_document);
    _currentSnapshot = _createSnapshot(_lastRichDocument);
  }

  _EditableBlock _makeBlock(NoteBlockData data) {
    late final _EditableBlock block;
    block = _EditableBlock(
      type: data.type,
      checked: data.checked,
      attachmentPath: data.attachmentPath,
      indent: data.indent,
      controller: _BlockTextEditingController(
        text: data.text,
        styles: data.styles,
      ),
      focusNode: FocusNode(),
    );
    block.controller.addListener(_syncDocument);
    block.focusNode.addListener(() {
      if (!block.focusNode.hasFocus || !mounted) return;
      final index = _blocks.indexOf(block);
      if (index >= 0) {
        _activeIndex = index;
        activeType.value = block.type;
        _refreshActiveFormat();
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
        indent: block.indent,
        styles: block.controller.styleRanges,
      ),
  ];

  void _syncDocument() {
    _refreshActiveFormat();
    if (_syncing) return;
    final text = NoteBlockCodec.encode(_document);
    if (widget.controller.text != text) {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    final richDocument = NoteRichDocumentCodec.encode(_document);
    _recordHistory(richDocument);
    if (_lastRichDocument != richDocument) {
      _lastRichDocument = richDocument;
      widget.onRichContentChanged?.call(richDocument);
    }
  }

  _EditorSnapshot _createSnapshot(String richDocument) {
    final block = _blocks.isEmpty
        ? null
        : _blocks[_activeIndex.clamp(0, _blocks.length - 1)];
    return _EditorSnapshot(
      richDocument: richDocument,
      activeIndex: _activeIndex,
      selection:
          block?.controller.visibleSelectionValue ??
          const TextSelection.collapsed(offset: 0),
    );
  }

  void _recordHistory(String richDocument) {
    final next = _createSnapshot(richDocument);
    if (_restoringHistory) {
      _currentSnapshot = next;
      return;
    }
    if (next.richDocument == _currentSnapshot.richDocument) {
      _currentSnapshot = next;
      return;
    }
    if (!_historyGroupOpen) {
      _undoStack.add(_currentSnapshot);
      if (_undoStack.length > 100) _undoStack.removeAt(0);
      _redoStack.clear();
      _historyGroupOpen = true;
    }
    _currentSnapshot = next;
    _historyGroupTimer?.cancel();
    _historyGroupTimer = Timer(
      const Duration(milliseconds: 650),
      _closeHistoryGroup,
    );
    _notifyHistoryChanged();
  }

  void _closeHistoryGroup() {
    _historyGroupTimer?.cancel();
    _historyGroupTimer = null;
    _historyGroupOpen = false;
  }

  void _beginDiscreteChange() => _closeHistoryGroup();

  void _endDiscreteChange() => _closeHistoryGroup();

  void _notifyHistoryChanged() {
    historyState.value = NoteHistoryState(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _closeHistoryGroup();
    final target = _undoStack.removeLast();
    _redoStack.add(_currentSnapshot);
    _restoreSnapshot(target);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.selectionClick();
    _closeHistoryGroup();
    final target = _redoStack.removeLast();
    _undoStack.add(_currentSnapshot);
    _restoreSnapshot(target);
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    final decoded = NoteRichDocumentCodec.tryDecode(snapshot.richDocument);
    if (decoded == null || decoded.isEmpty) return;
    _restoringHistory = true;
    _syncing = true;
    for (final block in _blocks) {
      block.dispose();
    }
    _blocks
      ..clear()
      ..addAll(decoded.map(_makeBlock));
    _activeIndex = snapshot.activeIndex.clamp(0, _blocks.length - 1);
    final plainText = NoteBlockCodec.encode(_document);
    widget.controller.value = TextEditingValue(
      text: plainText,
      selection: TextSelection.collapsed(offset: plainText.length),
    );
    _lastRichDocument = snapshot.richDocument;
    _currentSnapshot = snapshot;
    _syncing = false;
    _restoringHistory = false;
    activeType.value = _blocks[_activeIndex].type;
    setState(() {});
    widget.onRichContentChanged?.call(snapshot.richDocument);
    _notifyHistoryChanged();
    final block = _blocks[_activeIndex];
    if (block.type != NoteBlockType.divider &&
        block.type != NoteBlockType.attachment) {
      _refocus(block, selection: snapshot.selection);
    } else {
      _refreshActiveFormat();
    }
  }

  _EditableBlock? get _activeEditableBlock {
    if (_blocks.isEmpty || _activeIndex >= _blocks.length) return null;
    final block = _blocks[_activeIndex];
    if (block.type == NoteBlockType.divider ||
        block.type == NoteBlockType.attachment) {
      return null;
    }
    return block;
  }

  void _refreshActiveFormat() {
    final block = _activeEditableBlock;
    if (block == null) {
      activeFormat.value = const NoteEditorFormatState();
      return;
    }
    final selection = block.controller.visibleSelectionValue;
    final attributes = block.controller.attributesForSelection(selection);
    block.controller.typingAttributes = attributes;
    activeFormat.value = NoteEditorFormatState(
      bold: attributes.bold,
      underline: attributes.underline,
      fontSize: block.controller.uniformFontSize(selection),
      indent: block.indent,
    );
  }

  void toggleBold() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(bold: enabled),
    (attributes) => attributes.bold,
  );

  void toggleUnderline() => _toggleAttribute(
    (attributes, enabled) => attributes.copyWith(underline: enabled),
    (attributes) => attributes.underline,
  );

  void _toggleAttribute(
    NoteTextAttributes Function(NoteTextAttributes, bool) update,
    bool Function(NoteTextAttributes) read,
  ) {
    final block = _activeEditableBlock;
    if (block == null) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    final current = selection.isCollapsed
        ? block.controller.typingAttributes
        : block.controller.attributesForSelection(selection);
    if (selection.isCollapsed) {
      block.controller.typingAttributes = update(current, !read(current));
      activeFormat.value = NoteEditorFormatState(
        bold: block.controller.typingAttributes.bold,
        underline: block.controller.typingAttributes.underline,
        fontSize: block.controller.typingAttributes.fontSize,
        indent: block.indent,
      );
      _refocus(block, selection: selection);
      _endDiscreteChange();
      return;
    }
    block.controller.applyAttributes(
      selection,
      (attributes) => update(attributes, !read(current)),
    );
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void setFontSize(double fontSize) {
    final block = _activeEditableBlock;
    if (block == null) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    if (selection.isCollapsed) {
      block.controller.typingAttributes = block.controller.typingAttributes
          .copyWith(fontSize: fontSize);
      activeFormat.value = NoteEditorFormatState(
        bold: block.controller.typingAttributes.bold,
        underline: block.controller.typingAttributes.underline,
        fontSize: fontSize,
        indent: block.indent,
      );
      _refocus(block, selection: selection);
      _endDiscreteChange();
      return;
    }
    block.controller.applyAttributes(
      selection,
      (attributes) => attributes.copyWith(fontSize: fontSize),
    );
    _syncDocument();
    _refreshActiveFormat();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void changeIndent(int delta) {
    final block = _activeEditableBlock;
    if (block == null) return;
    final next = (block.indent + delta).clamp(0, 3);
    if (next == block.indent) return;
    _beginDiscreteChange();
    HapticFeedback.selectionClick();
    final selection = block.controller.visibleSelectionValue;
    setState(() => block.indent = next);
    _syncDocument();
    _refocus(block, selection: selection);
    _endDiscreteChange();
  }

  void toggleBlock(NoteBlockType type) {
    _beginDiscreteChange();
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
    _endDiscreteChange();
  }

  void insertDivider() {
    _beginDiscreteChange();
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
    final beforeStyles = current.controller.styleRangesFor(0, start);
    final afterStyles = current.controller.styleRangesFor(
      end,
      current.controller.visibleTextValue.length,
      shift: -end,
    );
    final divider = _makeBlock(const NoteBlockData(NoteBlockType.divider, ''));
    final next = _makeBlock(
      NoteBlockData(
        NoteBlockType.paragraph,
        after,
        indent: current.indent,
        styles: afterStyles,
      ),
    );
    _syncing = true;
    current.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, divider);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
  }

  void insertAttachmentReference(String filePath) {
    _beginDiscreteChange();
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
      _endDiscreteChange();
      return;
    }

    final selection = current.controller.visibleSelectionValue;
    final start = selection.isValid
        ? selection.start
        : current.controller.visibleTextValue.length;
    final end = selection.isValid ? selection.end : start;
    final before = current.controller.visibleTextValue.substring(0, start);
    final after = current.controller.visibleTextValue.substring(end);
    final beforeStyles = current.controller.styleRangesFor(0, start);
    final afterStyles = current.controller.styleRangesFor(
      end,
      current.controller.visibleTextValue.length,
      shift: -end,
    );
    final next = _makeBlock(
      NoteBlockData(
        NoteBlockType.paragraph,
        after,
        indent: current.indent,
        styles: afterStyles,
      ),
    );
    _syncing = true;
    current.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(_activeIndex + 1, reference);
      _blocks.insert(_activeIndex + 2, next);
      _activeIndex += 2;
      activeType.value = NoteBlockType.paragraph;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
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
    _endDiscreteChange();
  }

  void _splitBlock(_EditableBlock block, TextSelection replacedSelection) {
    if (!mounted) return;
    final index = _blocks.indexOf(block);
    if (index < 0) return;
    _beginDiscreteChange();
    final text = block.controller.visibleTextValue;
    final start = replacedSelection.start.clamp(0, text.length);
    final end = replacedSelection.end.clamp(start, text.length);
    final before = text.substring(0, start);
    final after = text.substring(end);
    final beforeStyles = block.controller.styleRangesFor(0, start);
    final afterStyles = block.controller.styleRangesFor(
      end,
      text.length,
      shift: -end,
    );

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
      _endDiscreteChange();
      return;
    }

    final nextType = switch (block.type) {
      NoteBlockType.bullet => NoteBlockType.bullet,
      NoteBlockType.ordered => NoteBlockType.ordered,
      NoteBlockType.todo => NoteBlockType.todo,
      NoteBlockType.quote => NoteBlockType.quote,
      _ => NoteBlockType.paragraph,
    };
    final next = _makeBlock(
      NoteBlockData(nextType, after, indent: block.indent, styles: afterStyles),
    );
    _syncing = true;
    block.controller.replaceVisibleText(before, beforeStyles);
    _syncing = false;
    setState(() {
      _blocks.insert(index + 1, next);
      _activeIndex = index + 1;
      activeType.value = nextType;
    });
    _syncDocument();
    _refocus(next, atStart: true);
    _endDiscreteChange();
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
    final mergedStyles = [
      ...previous.controller.styleRanges,
      ...block.controller.styleRangesFor(
        0,
        block.controller.visibleTextValue.length,
        shift: joinAt,
      ),
    ];
    _syncing = true;
    previous.controller.replaceVisibleText(
      previous.controller.visibleTextValue + block.controller.visibleTextValue,
      mergedStyles,
    );
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
    _beginDiscreteChange();

    if (block.type != NoteBlockType.paragraph) {
      setState(() {
        block.type = NoteBlockType.paragraph;
        block.checked = false;
        _activeIndex = index;
        activeType.value = NoteBlockType.paragraph;
      });
      _syncDocument();
      _refocus(block, atStart: true);
      _endDiscreteChange();
      return;
    }

    _mergeWithPrevious(block);
    _endDiscreteChange();
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

  void focusAtEnd() {
    final editable = _blocks.where(
      (item) =>
          item.type != NoteBlockType.divider &&
          item.type != NoteBlockType.attachment,
    );
    if (editable.isNotEmpty) _refocus(editable.last);
  }

  int _numberFor(int index) {
    var number = 1;
    for (var i = index - 1; i >= 0; i--) {
      if (_blocks[i].type != NoteBlockType.ordered ||
          _blocks[i].indent != _blocks[index].indent) {
        break;
      }
      number++;
    }
    return number;
  }

  @override
  void dispose() {
    _historyGroupTimer?.cancel();
    activeType.dispose();
    activeFormat.dispose();
    historyState.dispose();
    for (final block in _blocks) {
      block.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: focusAtEnd,
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
      padding: EdgeInsets.only(left: block.indent * 18 + (quote ? 10 : 0)),
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
    _beginDiscreteChange();
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
    _endDiscreteChange();
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
            _beginDiscreteChange();
            HapticFeedback.selectionClick();
            setState(() => block.checked = !block.checked);
            _syncDocument();
            _endDiscreteChange();
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
  List<NoteTextAttributes> _attributes;
  NoteTextAttributes typingAttributes = NoteTextAttributes.defaults;

  _BlockTextEditingController({
    String text = '',
    List<NoteTextStyleRange> styles = const [],
  }) : _attributes = _expandStyles(text.length, styles),
       super.fromValue(
         withBoundary(
           TextEditingValue(
             text: text,
             selection: TextSelection.collapsed(offset: text.length),
           ),
         ),
       );

  static List<NoteTextAttributes> _expandStyles(
    int length,
    List<NoteTextStyleRange> styles,
  ) {
    final expanded = List<NoteTextAttributes>.filled(
      length,
      NoteTextAttributes.defaults,
      growable: true,
    );
    for (final range in styles) {
      final start = range.start.clamp(0, length);
      final end = range.end.clamp(start, length);
      for (var index = start; index < end; index++) {
        expanded[index] = range.attributes;
      }
    }
    return expanded;
  }

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

  List<NoteTextStyleRange> get styleRanges {
    final ranges = <NoteTextStyleRange>[];
    if (_attributes.isEmpty) return ranges;
    var start = 0;
    var current = _attributes.first;
    for (var index = 1; index <= _attributes.length; index++) {
      final changed =
          index == _attributes.length || _attributes[index] != current;
      if (!changed) continue;
      if (current != NoteTextAttributes.defaults) {
        ranges.add(NoteTextStyleRange(start, index, current));
      }
      if (index < _attributes.length) {
        start = index;
        current = _attributes[index];
      }
    }
    return ranges;
  }

  List<NoteTextStyleRange> styleRangesFor(int start, int end, {int shift = 0}) {
    final ranges = <NoteTextStyleRange>[];
    for (final range in styleRanges) {
      final clippedStart = range.start.clamp(start, end);
      final clippedEnd = range.end.clamp(start, end);
      if (clippedStart < clippedEnd) {
        ranges.add(
          NoteTextStyleRange(
            clippedStart + shift,
            clippedEnd + shift,
            range.attributes,
          ),
        );
      }
    }
    return ranges;
  }

  NoteTextAttributes attributesForSelection(TextSelection selection) {
    if (_attributes.isEmpty) return typingAttributes;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.extentOffset : 0;
      final index = offset <= 0
          ? 0
          : (offset - 1).clamp(0, _attributes.length - 1);
      return _attributes[index];
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    if (start == end) return typingAttributes;
    final selected = _attributes.sublist(start, end);
    final first = selected.first;
    return NoteTextAttributes(
      bold: selected.every((attributes) => attributes.bold),
      underline: selected.every((attributes) => attributes.underline),
      fontSize:
          selected.every((attributes) => attributes.fontSize == first.fontSize)
          ? first.fontSize
          : NoteTextAttributes.defaultFontSize,
    );
  }

  double? uniformFontSize(TextSelection selection) {
    if (_attributes.isEmpty) return typingAttributes.fontSize;
    if (!selection.isValid || selection.isCollapsed) {
      return attributesForSelection(selection).fontSize;
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    if (start == end) return typingAttributes.fontSize;
    final size = _attributes[start].fontSize;
    return _attributes
            .sublist(start, end)
            .every((attributes) => attributes.fontSize == size)
        ? size
        : null;
  }

  void applyAttributes(
    TextSelection selection,
    NoteTextAttributes Function(NoteTextAttributes) update,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      typingAttributes = update(attributesForSelection(selection));
      notifyListeners();
      return;
    }
    final start = selection.start.clamp(0, _attributes.length);
    final end = selection.end.clamp(start, _attributes.length);
    for (var index = start; index < end; index++) {
      _attributes[index] = update(_attributes[index]);
    }
    typingAttributes = attributesForSelection(selection);
    notifyListeners();
  }

  void replaceVisibleText(String text, List<NoteTextStyleRange> styles) {
    _attributes = _expandStyles(text.length, styles);
    typingAttributes = _attributes.isEmpty
        ? NoteTextAttributes.defaults
        : _attributes.last;
    super.value = withBoundary(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    final normalized = withBoundary(newValue);
    final oldText = visibleText(super.text);
    final newText = visibleText(normalized.text);
    if (oldText != newText) _reconcileStyles(oldText, newText);
    super.value = normalized;
  }

  void _reconcileStyles(String oldText, String newText) {
    if (_attributes.length != oldText.length) {
      _attributes = List<NoteTextAttributes>.filled(
        oldText.length,
        NoteTextAttributes.defaults,
        growable: true,
      );
    }
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }
    final oldEnd = oldText.length - suffix;
    final insertedLength = newText.length - prefix - suffix;
    _attributes.replaceRange(
      prefix,
      oldEnd,
      List<NoteTextAttributes>.filled(insertedLength, typingAttributes),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[TextSpan(text: boundary, style: base)];
    final text = visibleTextValue;
    if (text.isEmpty) return TextSpan(style: base, children: children);
    bool isComposing(int rawOffset) =>
        withComposing &&
        value.composing.isValid &&
        rawOffset >= value.composing.start &&
        rawOffset < value.composing.end;
    var start = 0;
    while (start < text.length) {
      final attributes = start < _attributes.length
          ? _attributes[start]
          : NoteTextAttributes.defaults;
      final rawIndex = start + boundary.length;
      final composing = isComposing(rawIndex);
      var end = start + 1;
      while (end < text.length) {
        final next = end < _attributes.length
            ? _attributes[end]
            : NoteTextAttributes.defaults;
        final nextComposing = isComposing(end + boundary.length);
        if (next != attributes || nextComposing != composing) break;
        end++;
      }
      final decorations = <TextDecoration>[
        if (base.decoration != null) base.decoration!,
        if (attributes.underline || composing) TextDecoration.underline,
      ];
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: base.copyWith(
            fontWeight: attributes.bold ? FontWeight.w700 : base.fontWeight,
            fontSize: attributes.fontSize,
            decoration: decorations.isEmpty
                ? null
                : TextDecoration.combine(decorations),
          ),
        ),
      );
      start = end;
    }
    return TextSpan(style: base, children: children);
  }
}

class _EditableBlock {
  NoteBlockType type;
  bool checked;
  int indent;
  final String? attachmentPath;
  final _BlockTextEditingController controller;
  final FocusNode focusNode;

  _EditableBlock({
    required this.type,
    required this.checked,
    required this.indent,
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
