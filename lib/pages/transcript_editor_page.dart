import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../widgets/editor_context_menu.dart';

class TranscriptEditorPage extends StatefulWidget {
  final String initialText;

  const TranscriptEditorPage({super.key, required this.initialText});

  @override
  State<TranscriptEditorPage> createState() => _TranscriptEditorPageState();
}

class _TranscriptEditorPageState extends State<TranscriptEditorPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText)
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

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        toolbarHeight: 64,
        leading: IconButton(
          key: const Key('cancel-transcript-edit'),
          tooltip: context.l10n.cancel,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          context.l10n.editTranscript,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('save-transcript-edit'),
              onPressed: text.trim().isEmpty ? null : _save,
              child: Text(context.l10n.save),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: AppColors.moss,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.transcriptLocalOnlyDescription,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.large),
                  ),
                  child: TextField(
                    key: const Key('transcript-editor-field'),
                    controller: _controller,
                    contextMenuBuilder: buildAppEditableTextContextMenu,
                    autofocus: true,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      height: 1.65,
                    ),
                    decoration: InputDecoration(
                      hintText: context.l10n.transcriptHint,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  context.l10n.transcriptCharacterCount(text.characters.length),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
