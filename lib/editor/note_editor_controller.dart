// Flutter Quill 11.5.1 exposes its typed clipboard hooks as experimental. The
// dependency is pinned and these hooks are covered by our editor tests.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:quill_native_bridge/quill_native_bridge.dart';

import '../models/note.dart';
import '../models/note_document.dart';
import 'note_assistant_editing.dart';

typedef NoteImageImporter = Future<NoteAsset?> Function(Uint8List bytes);
typedef NoteClipboardImageReader = Future<Uint8List?> Function();
typedef NoteAssetDisposer = Future<void> Function(NoteAsset asset);

final class NoteEditorSnapshot {
  const NoteEditorSnapshot({required this.document, required this.assets});

  final NoteDocument document;
  final List<NoteAsset> assets;
}

/// Tracks one streamed AI insertion as an atomic editor interaction.
///
/// The document is read-only while the session is active, so every streamed
/// replacement can be validated against the previous frame. The original
/// Delta remains available for a one-tap undo after generation completes.
final class NoteAssistantInsertionSession {
  NoteAssistantInsertionSession._({
    required this.originalDocument,
    required this.originalSelection,
    required this.offset,
    required this.replacementLength,
    required this.expectedDocument,
  });

  final Delta originalDocument;
  final TextSelection originalSelection;
  final int offset;
  int replacementLength;
  String expectedDocument;
  bool acceptingUpdates = true;
}

/// Owns one Quill editing session without projecting the whole document on
/// every key stroke.
///
/// Full validation and attachment reconciliation happen only when [snapshot]
/// is requested by autosave, sharing, or another document consumer.
final class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required NoteDocument document,
    required Iterable<NoteAsset> assets,
    NoteImageImporter? importImage,
    this.discardImportedAsset,
    NoteClipboardImageReader? readClipboardImage,
  }) : _assets = {for (final asset in assets) asset.id: asset},
       _importImage = importImage,
       _readClipboardImage =
           readClipboardImage ??
           (importImage == null ? null : _readSystemClipboardImage) {
    quillController = QuillController(
      document: document.toQuillDocument(),
      selection: const TextSelection.collapsed(offset: 0),
      config: QuillControllerConfig(
        clipboardConfig: QuillClipboardConfig(
          onClipboardPaste: _pasteClipboardImage,
          onRichTextPaste: _sanitizeRichTextPaste,
          enableExternalRichPaste: true,
        ),
      ),
    );
    _changes = quillController.document.changes.listen((_) {
      contentRevision++;
      notifyListeners();
    });
  }

  late final QuillController quillController;
  late final StreamSubscription<DocChange> _changes;
  final Map<NoteAttachmentId, NoteAsset> _assets;
  final NoteImageImporter? _importImage;
  final NoteAssetDisposer? discardImportedAsset;
  final NoteClipboardImageReader? _readClipboardImage;

  int contentRevision = 0;

  List<NoteAsset> get assets => List.unmodifiable(_assets.values);

  NoteAsset? asset(NoteAttachmentId id) => _assets[id];

  NoteEditorSnapshot snapshot() {
    final document = NoteDocument.fromDelta(quillController.document.toDelta());
    final ids = document.project().referencedAttachmentIds;
    final reconciledAssets = <NoteAsset>[];
    for (final id in ids) {
      final asset = _assets[id];
      if (asset == null) {
        throw StateError('The document references a missing asset: $id');
      }
      reconciledAssets.add(asset);
    }
    return NoteEditorSnapshot(
      document: document,
      assets: List.unmodifiable(reconciledAssets),
    );
  }

  NoteAssistantAnchor captureAssistantAnchor() {
    final delta = quillController.document.toDelta();
    final plainText = quillController.document.toPlainText();
    final rawSelection = quillController.selection;
    final documentEnd = plainText.isEmpty ? 0 : plainText.length - 1;
    final start = rawSelection.start.clamp(0, documentEnd);
    final end = rawSelection.end.clamp(start, documentEnd);
    final extent = rawSelection.extentOffset.clamp(0, documentEnd);
    final previousNewline = extent == 0
        ? -1
        : plainText.lastIndexOf('\n', extent - 1);
    final lineStart = previousNewline + 1;
    final nextNewline = plainText.indexOf('\n', extent);
    final lineEnd = nextNewline < 0 ? documentEnd : nextNewline;
    String readable(String value) => value
        .replaceAll(NoteDocument.objectReplacementCharacter, '')
        .trimRight();
    return NoteAssistantAnchor(
      expectedDocument: encodeAssistantExpectedDocument(delta),
      selection: TextSelection(baseOffset: start, extentOffset: end),
      lineStart: lineStart,
      lineEnd: lineEnd,
      selectedText: readable(plainText.substring(start, end)),
      currentLineText: readable(plainText.substring(lineStart, lineEnd)),
    );
  }

  NoteAssistantInsertionSession beginAssistantInsertion() {
    final document = quillController.document.toDelta();
    final documentEnd = (quillController.document.length - 1).clamp(
      0,
      quillController.document.length,
    );
    final rawSelection = quillController.selection;
    final start = rawSelection.start.clamp(0, documentEnd);
    final end = rawSelection.end.clamp(start, documentEnd);
    return NoteAssistantInsertionSession._(
      originalDocument: Delta.fromJson(document.toJson()),
      originalSelection: TextSelection(baseOffset: start, extentOffset: end),
      offset: start,
      replacementLength: end - start,
      expectedDocument: encodeAssistantExpectedDocument(document),
    );
  }

  bool updateAssistantInsertion(
    NoteAssistantInsertionSession session,
    String markdown,
  ) {
    if (!session.acceptingUpdates ||
        markdown.trim().isEmpty ||
        encodeAssistantExpectedDocument(quillController.document.toDelta()) !=
            session.expectedDocument) {
      return false;
    }
    final generated = NoteAssistantMarkdownCodec.decode(markdown);
    final replacement = _isSinglePlainParagraph(generated)
        ? _deltaWithoutTerminalNewline(generated)
        : generated;
    quillController.replaceText(
      session.offset,
      session.replacementLength,
      replacement,
      null,
    );
    final replacementContentLength = _contentLength(replacement);
    session.replacementLength = replacementContentLength;
    session.expectedDocument = encodeAssistantExpectedDocument(
      quillController.document.toDelta(),
    );
    final caret = (session.offset + replacementContentLength).clamp(
      0,
      quillController.document.length - 1,
    );
    quillController.updateSelection(
      TextSelection.collapsed(offset: caret),
      ChangeSource.local,
    );
    return true;
  }

  void finishAssistantInsertion(NoteAssistantInsertionSession session) {
    session.acceptingUpdates = false;
  }

  bool revertAssistantInsertion(NoteAssistantInsertionSession session) {
    if (encodeAssistantExpectedDocument(quillController.document.toDelta()) !=
        session.expectedDocument) {
      return false;
    }
    quillController.replaceText(
      0,
      quillController.document.length,
      Delta.fromJson(session.originalDocument.toJson()),
      null,
    );
    final documentEnd = (quillController.document.length - 1).clamp(
      0,
      quillController.document.length,
    );
    quillController.updateSelection(
      TextSelection(
        baseOffset: session.originalSelection.baseOffset.clamp(0, documentEnd),
        extentOffset: session.originalSelection.extentOffset.clamp(
          0,
          documentEnd,
        ),
      ),
      ChangeSource.local,
    );
    session.acceptingUpdates = false;
    return true;
  }

  bool applyAssistantMarkdown({
    required NoteAssistantAnchor anchor,
    required NoteAssistantEditScope scope,
    required NoteAssistantEditPlacement placement,
    required String markdown,
  }) {
    if (markdown.trim().isEmpty ||
        encodeAssistantExpectedDocument(quillController.document.toDelta()) !=
            anchor.expectedDocument) {
      return false;
    }
    final generated = NoteAssistantMarkdownCodec.decode(markdown);
    final documentLength = quillController.document.length;
    late final int offset;
    late final int length;
    late final Delta replacement;

    if (placement == NoteAssistantEditPlacement.append) {
      offset = (documentLength - 1).clamp(0, documentLength);
      length = 0;
      replacement = Delta();
      if (documentLength > 1) replacement.insert('\n');
      final generatedBody = _deltaWithoutTerminalNewline(generated);
      for (final operation in generatedBody.operations) {
        replacement.push(operation);
      }
    } else if (placement == NoteAssistantEditPlacement.insertBelow) {
      offset = (anchor.lineEnd + 1).clamp(0, documentLength);
      length = 0;
      replacement = generated;
    } else {
      switch (scope) {
        case NoteAssistantEditScope.selection:
          offset = anchor.selection.start;
          length = anchor.selection.end - anchor.selection.start;
          replacement = _isSinglePlainParagraph(generated)
              ? _deltaWithoutTerminalNewline(generated)
              : generated;
        case NoteAssistantEditScope.currentLine:
          offset = anchor.lineStart;
          length = anchor.lineEnd - anchor.lineStart + 1;
          replacement = generated;
        case NoteAssistantEditScope.document:
          offset = 0;
          length = documentLength;
          replacement = generated;
      }
    }

    quillController.replaceText(offset, length, replacement, null);
    final caret = (offset + _contentLength(replacement)).clamp(
      0,
      quillController.document.length - 1,
    );
    quillController.updateSelection(
      TextSelection.collapsed(offset: caret),
      ChangeSource.local,
    );
    return true;
  }

  static bool _isSinglePlainParagraph(Delta delta) {
    final operations = delta.operations;
    if (operations.isEmpty || operations.last.data != '\n') return false;
    if (operations.last.attributes?.isNotEmpty == true) return false;
    return operations
        .take(operations.length - 1)
        .where((operation) => operation.data is String)
        .every((operation) => !(operation.data as String).contains('\n'));
  }

  static Delta _deltaWithoutTerminalNewline(Delta source) {
    final json = source.toJson().map(Map<String, dynamic>.from).toList();
    if (json.isEmpty) return Delta();
    final last = json.last;
    if (last['insert'] == '\n') {
      json.removeLast();
    } else if (last['insert'] is String &&
        (last['insert'] as String).endsWith('\n')) {
      final value = last['insert'] as String;
      if (value.length == 1) {
        json.removeLast();
      } else {
        last['insert'] = value.substring(0, value.length - 1);
      }
    }
    return Delta.fromJson(json);
  }

  static int _contentLength(Delta delta) => delta.operations.fold(
    0,
    (length, operation) => length + (operation.length ?? 0),
  );

  Future<bool> importImageBytes(Uint8List bytes) async {
    final importer = _importImage;
    if (importer == null) return false;
    final asset = await importer(bytes);
    if (asset == null) return false;
    try {
      insertAsset(asset);
    } catch (_) {
      await discardImportedAsset?.call(asset);
      rethrow;
    }
    return true;
  }

  void insertAsset(NoteAsset asset) {
    if (_assets.containsKey(asset.id)) {
      throw ArgumentError('The asset already exists in this note: ${asset.id}');
    }
    _assets[asset.id] = asset;
    try {
      _insertBlockEmbed(NoteEmbed.attachment(asset.id));
    } catch (_) {
      _assets.remove(asset.id);
      rethrow;
    }
  }

  void insertDivider() => _insertBlockEmbed(const NoteEmbed.divider());

  void removeEmbedAt(int documentOffset) {
    final removeLength = quillController.document.length > 2 ? 2 : 1;
    quillController.replaceText(
      documentOffset,
      removeLength,
      '',
      TextSelection.collapsed(offset: documentOffset),
    );
  }

  void _insertBlockEmbed(NoteEmbed embed) {
    final selection = quillController.selection;
    final start = selection.start < 0 ? 0 : selection.start;
    final end = selection.end < start ? start : selection.end;
    final plainText = quillController.document.toPlainText();
    final startsAtLineBoundary =
        start == 0 || plainText.codeUnitAt(start - 1) == 10;
    final insertion = Delta();
    if (!startsAtLineBoundary) insertion.insert('\n');
    insertion
      ..insert(embed.toDeltaData())
      ..insert('\n');
    quillController.replaceText(start, end - start, insertion, null);
    final caret = start + (startsAtLineBoundary ? 0 : 1) + 2;
    quillController.updateSelection(
      TextSelection.collapsed(offset: caret),
      ChangeSource.local,
    );
  }

  Future<bool> _pasteClipboardImage() async {
    final reader = _readClipboardImage;
    if (reader == null || _importImage == null) return false;
    final bytes = await reader();
    if (bytes == null) return false;
    await importImageBytes(bytes);
    // Once an image is present, do not fall through and insert an unrelated
    // plain-text representation from the same clipboard item.
    return true;
  }

  static Future<Uint8List?> _readSystemClipboardImage() async {
    final bridge = QuillNativeBridge();
    if (!await bridge.isSupported(QuillNativeBridgeFeature.getClipboardImage)) {
      return null;
    }
    return bridge.getClipboardImage();
  }

  Future<Delta?> _sanitizeRichTextPaste(Delta pasted, bool isExternal) async {
    final clean = Delta();
    for (final operation in pasted.operations) {
      if (!operation.isInsert) continue;
      final data = operation.data;
      if (data is String) {
        clean.insert(data, operation.attributes);
        continue;
      }
      if (isExternal) continue;
      try {
        final embed = NoteEmbed.parse(data);
        final id = embed.attachmentId;
        if (id == null || _assets.containsKey(id)) {
          clean.insert(embed.toDeltaData());
        }
      } on FormatException {
        // Built-in URL/path images and unknown embeds never enter the domain
        // document. Images are imported through the managed byte pipeline.
      }
    }
    return clean;
  }

  @override
  void dispose() {
    _changes.cancel();
    quillController.dispose();
    super.dispose();
  }
}
