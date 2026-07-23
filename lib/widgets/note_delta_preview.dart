import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_document.dart';

typedef NotePreviewEmbedLabel =
    String Function(NoteEmbed embed, NoteAsset? asset);

/// A lightweight card projection of Delta content.
///
/// It preserves inline emphasis without creating an editor controller for
/// every list row. Markdown markers never participate in this path.
final class NoteDeltaPreview extends StatelessWidget {
  const NoteDeltaPreview({
    required this.note,
    this.maxLines = 3,
    this.style,
    this.embedLabel,
    this.includeAttachmentLabels = true,
    super.key,
  });

  final Note note;
  final int maxLines;
  final TextStyle? style;
  final NotePreviewEmbedLabel? embedLabel;
  final bool includeAttachmentLabels;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        style ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle();
    final assets = note.assetsById;
    final spans = <InlineSpan>[];
    final operations = note.document.toDelta().operations;
    var removeNextAttachmentLineBreak = false;
    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      final data = operation.data;
      if (data is String) {
        var value = data;
        if (removeNextAttachmentLineBreak && value.startsWith('\n')) {
          value = value.substring(1);
        }
        removeNextAttachmentLineBreak = false;
        if (index == operations.length - 1 && value.endsWith('\n')) {
          value = value.substring(0, value.length - 1);
        }
        if (value.isEmpty) continue;
        spans.add(
          TextSpan(
            text: value,
            style: _inlineStyle(baseStyle, operation.attributes),
          ),
        );
        continue;
      }
      final embed = NoteEmbed.parse(data);
      final asset = assets[embed.attachmentId];
      if (!includeAttachmentLabels && embed.kind == NoteEmbedKind.attachment) {
        removeNextAttachmentLineBreak = true;
        continue;
      }
      final label =
          embedLabel?.call(embed, asset) ??
          switch (embed.kind) {
            NoteEmbedKind.divider => '  —  ',
            NoteEmbedKind.table => embed.table!.plainText,
            NoteEmbedKind.attachment =>
              asset == null ? '【附件】' : '【${asset.displayTitle}】',
          };
      spans.add(
        TextSpan(
          text: label,
          style: baseStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      key: const Key('note-delta-preview-text'),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle,
    );
  }

  static TextStyle _inlineStyle(
    TextStyle base,
    Map<String, dynamic>? attributes,
  ) {
    final values = attributes ?? const <String, dynamic>{};
    final decorations = <TextDecoration>[];
    if (values['underline'] == true) decorations.add(TextDecoration.underline);
    if (values['strike'] == true) decorations.add(TextDecoration.lineThrough);
    return base.copyWith(
      fontWeight: values['bold'] == true ? FontWeight.w700 : null,
      fontStyle: values['italic'] == true ? FontStyle.italic : null,
      fontFamily: values['code'] == true ? 'monospace' : null,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
    );
  }
}
