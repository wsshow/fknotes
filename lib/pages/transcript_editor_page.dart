import 'package:flutter/material.dart';

import '../app.dart';
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
        leading: IconButton(
          key: const Key('cancel-transcript-edit'),
          tooltip: '取消',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text(
          '编辑转写文字',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('save-transcript-edit'),
              onPressed: text.trim().isEmpty ? null : _save,
              child: const Text('保存'),
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
              const Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: AppColors.moss,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '仅修改本地转写文字，原始录音不会改变',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
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
                    decoration: const InputDecoration(
                      hintText: '输入转写文字',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${text.characters.length} 字',
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
