import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'editor_context_menu.dart';

/// Edits the complete, ordered tag set as one modal transaction.
final class NoteTagsEditorSheet extends StatefulWidget {
  const NoteTagsEditorSheet({required this.initialTags, super.key});

  final List<String> initialTags;

  @override
  State<NoteTagsEditorSheet> createState() => _NoteTagsEditorSheetState();
}

final class _NoteTagsEditorSheetState extends State<NoteTagsEditorSheet> {
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

  static List<String> _parseTags(String value) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in value.split(RegExp('[,，]'))) {
      final tag = raw.trim();
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      normalized.add(tag);
      if (normalized.length == 8) break;
    }
    return normalized;
  }

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
                      context.l10n.editTags,
                      style: Theme.of(context).textTheme.titleLarge,
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
              Text(
                context.l10n.tagsDescription,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('note-tags-field'),
                controller: _controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: _changed,
                onSubmitted: (_) => _finish(),
                decoration: InputDecoration(
                  labelText: context.l10n.tags,
                  hintText: context.l10n.tagsHint,
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
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('save-note-tags'),
                      onPressed: _finish,
                      child: Text(context.l10n.completed),
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
