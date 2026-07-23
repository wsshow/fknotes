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

typedef NoteImageImporter = Future<NoteAsset?> Function(Uint8List bytes);
typedef NoteClipboardImageReader = Future<Uint8List?> Function();

final class NoteEditorSnapshot {
  const NoteEditorSnapshot({required this.document, required this.assets});

  final NoteDocument document;
  final List<NoteAsset> assets;
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

  Future<bool> importImageBytes(Uint8List bytes) async {
    final importer = _importImage;
    if (importer == null) return false;
    final asset = await importer(bytes);
    if (asset == null) return false;
    insertAsset(asset);
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
