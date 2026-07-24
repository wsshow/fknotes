import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import 'editor_context_menu.dart';

final class NoteAttachmentTitleResult {
  const NoteAttachmentTitleResult(this.displayName);

  final String? displayName;
}

Future<NoteAttachmentTitleResult?> showNoteAttachmentTitleSheet(
  BuildContext context, {
  required String initialValue,
  required Key fieldKey,
}) => showModalBottomSheet<NoteAttachmentTitleResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      NoteAttachmentTitleSheet(initialValue: initialValue, fieldKey: fieldKey),
);

/// A keyboard-safe attachment title form shared by image and audio assets.
///
/// Text-entry tasks use the same bottom-sheet structure as tag editing, while
/// short confirmations remain regular dialogs.
final class NoteAttachmentTitleSheet extends StatefulWidget {
  const NoteAttachmentTitleSheet({
    required this.initialValue,
    required this.fieldKey,
    super.key,
  });

  final String initialValue;
  final Key fieldKey;

  @override
  State<NoteAttachmentTitleSheet> createState() =>
      _NoteAttachmentTitleSheetState();
}

final class _NoteAttachmentTitleSheetState
    extends State<NoteAttachmentTitleSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
    context,
    NoteAttachmentTitleResult(_controller.text.trim()),
  );

  void _restoreOriginalName() =>
      Navigator.pop(context, const NoteAttachmentTitleResult(null));

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
                      context.l10n.editAttachmentTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_controller.text.length}/120',
                    key: const Key('attachment-title-count'),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.attachmentTitleDescription,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextField(
                key: widget.fieldKey,
                controller: _controller,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                autofocus: true,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: context.l10n.attachmentTitle,
                  hintText: context.l10n.attachmentTitleHint,
                  counterText: '',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('restore-attachment-title'),
                  onPressed: _restoreOriginalName,
                  child: Text(context.l10n.restoreOriginalFileName),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('cancel-attachment-title'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('save-attachment-title'),
                      onPressed: _save,
                      child: Text(context.l10n.save),
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
