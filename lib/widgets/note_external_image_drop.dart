import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../services/android_external_drop_service.dart';

const _maximumDroppedImageBytes = 20 * 1024 * 1024;

final class NoteDroppedImage {
  const NoteDroppedImage({required this.bytes, required this.originalName});

  final Uint8List bytes;
  final String originalName;
}

final class NoteDroppedImageBatch {
  const NoteDroppedImageBatch({
    required this.images,
    required this.rejectedCount,
  });

  final List<NoteDroppedImage> images;
  final int rejectedCount;
}

final class _DroppedFileSource {
  const _DroppedFileSource(this.file, {this.originalName, this.mimeType});

  final XFile file;
  final String? originalName;
  final String? mimeType;
}

typedef NoteExternalImageDropHandler =
    Future<void> Function(NoteDroppedImageBatch batch, int documentOffset);

/// Cross-application file drop target for the note editor.
///
/// Android drops are copied into app-owned cache files by the activity before
/// URI permissions expire. Other platforms use [DropTarget]'s [XFile] values.
final class NoteExternalImageDropRegion extends StatefulWidget {
  const NoteExternalImageDropRegion({
    required this.enabled,
    required this.captureDocumentOffset,
    required this.onDropImages,
    required this.onDropActiveChanged,
    required this.child,
    super.key,
  });

  final bool enabled;
  final int? Function(Offset globalPosition) captureDocumentOffset;
  final NoteExternalImageDropHandler onDropImages;
  final ValueChanged<bool> onDropActiveChanged;
  final Widget child;

  @override
  State<NoteExternalImageDropRegion> createState() =>
      _NoteExternalImageDropRegionState();
}

final class _NoteExternalImageDropRegionState
    extends State<NoteExternalImageDropRegion> {
  bool get _usesAndroidBridge =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_usesAndroidBridge) {
      AndroidExternalDropService.instance.addListener(_handleAndroidDrop);
    }
  }

  @override
  void dispose() {
    if (_usesAndroidBridge) {
      AndroidExternalDropService.instance.removeListener(_handleAndroidDrop);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    key: const Key('note-external-image-drop-region'),
    enable: widget.enabled && !_usesAndroidBridge,
    onDragEntered: (details) => _updateDrag(details.globalPosition),
    onDragUpdated: (details) => _updateDrag(details.globalPosition),
    onDragExited: (_) => widget.onDropActiveChanged(false),
    onDragDone: (details) {
      final documentOffset = widget.captureDocumentOffset(
        details.globalPosition,
      );
      widget.onDropActiveChanged(false);
      if (documentOffset == null) return;
      unawaited(
        _readAndDeliver(
          details.files.map(_DroppedFileSource.new).toList(growable: false),
          documentOffset,
          initialRejectedCount: 0,
        ),
      );
    },
    child: widget.child,
  );

  void _updateDrag(Offset globalPosition) {
    if (!widget.enabled) return;
    final documentOffset = widget.captureDocumentOffset(globalPosition);
    widget.onDropActiveChanged(documentOffset != null);
  }

  void _handleAndroidDrop(AndroidExternalDropEvent event) {
    if (!mounted || !widget.enabled) return;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final globalPosition = event.physicalPosition / devicePixelRatio;
    switch (event.type) {
      case AndroidExternalDropEventType.entered:
      case AndroidExternalDropEventType.updated:
        _updateDrag(globalPosition);
      case AndroidExternalDropEventType.exited:
        widget.onDropActiveChanged(false);
      case AndroidExternalDropEventType.done:
        final documentOffset = widget.captureDocumentOffset(globalPosition);
        widget.onDropActiveChanged(false);
        if (documentOffset == null) {
          unawaited(
            AndroidExternalDropService.instance.deleteTemporaryFiles(
              event.files.map((file) => file.path),
            ),
          );
          return;
        }
        final files = event.files
            .map(
              (file) => _DroppedFileSource(
                XFile(
                  file.path,
                  mimeType: file.mimeType,
                  length: file.byteLength,
                ),
                originalName: file.name,
                mimeType: file.mimeType,
              ),
            )
            .toList(growable: false);
        unawaited(
          _readAndDeliver(
            files,
            documentOffset,
            initialRejectedCount: event.rejectedCount,
            temporaryPaths: event.files.map((file) => file.path).toList(),
          ),
        );
    }
  }

  Future<void> _readAndDeliver(
    List<_DroppedFileSource> files,
    int documentOffset, {
    required int initialRejectedCount,
    List<String> temporaryPaths = const [],
  }) async {
    try {
      final values = await Future.wait(files.map(_readDroppedImage));
      final images = values.whereType<NoteDroppedImage>().toList(
        growable: false,
      );
      await widget.onDropImages(
        NoteDroppedImageBatch(
          images: images,
          rejectedCount: initialRejectedCount + values.length - images.length,
        ),
        documentOffset,
      );
    } finally {
      if (temporaryPaths.isNotEmpty) {
        await AndroidExternalDropService.instance.deleteTemporaryFiles(
          temporaryPaths,
        );
      }
    }
  }
}

Future<NoteDroppedImage?> _readDroppedImage(_DroppedFileSource source) async {
  final file = source.file;
  final preferredName = source.originalName?.trim() ?? '';
  final fileName = file.name.trim();
  final name = preferredName.isNotEmpty
      ? preferredName
      : fileName.isNotEmpty
      ? fileName
      : p.basename(file.path);
  final mimeType =
      (source.mimeType ?? file.mimeType)?.trim().toLowerCase() ?? '';
  if (!_isSupportedImage(name, mimeType)) return null;
  final byteLength = await file.length();
  if (byteLength <= 0 || byteLength > _maximumDroppedImageBytes) return null;
  return NoteDroppedImage(
    bytes: await file.readAsBytes(),
    originalName: name.trim().isEmpty ? '拖入的图片' : name,
  );
}

bool _isSupportedImage(String name, String mimeType) {
  if (const {
    'image/bmp',
    'image/gif',
    'image/jpeg',
    'image/png',
    'image/tiff',
    'image/webp',
  }.contains(mimeType)) {
    return true;
  }
  return const {
    '.bmp',
    '.gif',
    '.jpeg',
    '.jpg',
    '.png',
    '.tif',
    '.tiff',
    '.webp',
  }.contains(p.extension(name).toLowerCase());
}
