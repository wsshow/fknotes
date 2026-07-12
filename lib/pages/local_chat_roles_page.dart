import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/local_chat.dart';
import '../services/local_chat_store.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';

class LocalChatRolesPage extends StatefulWidget {
  final String? selectedPersonaId;
  final List<LocalChatPersona>? initialPersonas;

  const LocalChatRolesPage({
    super.key,
    this.selectedPersonaId,
    this.initialPersonas,
  });

  @override
  State<LocalChatRolesPage> createState() => _LocalChatRolesPageState();
}

class _LocalChatRolesPageState extends State<LocalChatRolesPage> {
  final _store = LocalChatStore.instance;
  List<LocalChatPersona> _personas = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialPersonas = widget.initialPersonas;
    if (initialPersonas == null) {
      unawaited(_load());
    } else {
      _personas = initialPersonas;
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final personas = await _store.loadPersonas();
      if (!mounted) return;
      setState(() {
        _personas = personas;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _createPersona() async {
    final draft = await _showEditor();
    if (draft == null || !mounted) return;
    try {
      await _store.savePersona(
        _store.createPersona(
          name: draft.name,
          description: draft.description,
          systemPrompt: draft.systemPrompt,
        ),
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editPersona(LocalChatPersona persona) async {
    if (persona.builtIn) return;
    final draft = await _showEditor(persona: persona);
    if (draft == null || !mounted) return;
    try {
      await _store.savePersona(
        persona.copyWith(
          name: draft.name,
          description: draft.description,
          systemPrompt: draft.systemPrompt,
          updatedAt: DateTime.now(),
        ),
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deletePersona(LocalChatPersona persona) async {
    if (persona.builtIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${persona.name}”？'),
        content: const Text('使用这个角色的对话会切换回通用助手，聊天记录不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _store.deletePersona(persona.id);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<_PersonaDraft?> _showEditor({LocalChatPersona? persona}) =>
      showModalBottomSheet<_PersonaDraft>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PersonaEditorSheet(persona: persona),
      );

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error
              .toString()
              .replaceFirst('FormatException: ', '')
              .replaceFirst('Bad state: ', ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('角色管理'),
      actions: [
        IconButton(
          key: const Key('local-chat-add-persona'),
          tooltip: '新建角色',
          onPressed: _loading ? null : _createPersona,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    floatingActionButton: _loading
        ? null
        : FloatingActionButton.extended(
            onPressed: _createPersona,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建角色'),
          ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _error != null
        ? Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
            children: [
              const Text(
                '角色决定本地模型回答问题时采用的身份、语气和规则。你可以在聊天中随时切换，所有设定只保存在本机。',
                style: TextStyle(color: AppColors.muted, height: 1.55),
              ),
              const SizedBox(height: 18),
              for (final persona in _personas) ...[
                _PersonaCard(
                  persona: persona,
                  selected: persona.id == widget.selectedPersonaId,
                  onEdit: () => _editPersona(persona),
                  onDelete: () => _deletePersona(persona),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
  );
}

class _PersonaCard extends StatelessWidget {
  final LocalChatPersona persona;
  final bool selected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
    decoration: BoxDecoration(
      color: selected ? AppColors.softGreen : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: selected
            ? AppColors.moss.withValues(alpha: .35)
            : AppColors.line,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.softCoral,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.psychology_alt_outlined,
            color: AppColors.coral,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      persona.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (persona.builtIn) ...[
                    const SizedBox(width: 7),
                    const _PersonaBadge(label: '内置'),
                  ],
                  if (selected) ...[
                    const SizedBox(width: 7),
                    const _PersonaBadge(label: '当前'),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                persona.description.isEmpty ? '未填写角色说明' : persona.description,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (!persona.builtIn)
          AppAnchoredMenuButton<String>(
            tooltip: '角色操作',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            actions: const [
              AppMenuAction(
                value: 'edit',
                icon: Icons.edit_outlined,
                label: '编辑角色',
              ),
              AppMenuAction(
                value: 'delete',
                icon: Icons.delete_outline_rounded,
                label: '删除角色',
                destructive: true,
              ),
            ],
          )
        else
          const SizedBox(width: 40),
      ],
    ),
  );
}

class _PersonaBadge extends StatelessWidget {
  final String label;
  const _PersonaBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.softBlue,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _PersonaDraft {
  final String name;
  final String description;
  final String systemPrompt;

  const _PersonaDraft({
    required this.name,
    required this.description,
    required this.systemPrompt,
  });
}

class _PersonaEditorSheet extends StatefulWidget {
  final LocalChatPersona? persona;
  const _PersonaEditorSheet({this.persona});

  @override
  State<_PersonaEditorSheet> createState() => _PersonaEditorSheetState();
}

class _PersonaEditorSheetState extends State<_PersonaEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.persona?.name ?? '');
    _description = TextEditingController(
      text: widget.persona?.description ?? '',
    );
    _prompt = TextEditingController(text: widget.persona?.systemPrompt ?? '');
    for (final controller in [_name, _description, _prompt]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final controller in [_name, _description, _prompt]) {
      controller
        ..removeListener(_changed)
        ..dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _prompt.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(
      context,
      _PersonaDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        systemPrompt: _prompt.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: FractionallySizedBox(
        heightFactor: .86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.persona == null ? '新建角色' : '编辑角色',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              const Text(
                '角色名称用于切换；系统提示词会在每次请求中作为最高优先级的本地指令。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('local-chat-persona-name'),
                controller: _name,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                autofocus: widget.persona == null,
                maxLength: 30,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '角色名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('local-chat-persona-description'),
                controller: _description,
                contextMenuBuilder: buildAppEditableTextContextMenu,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '简短说明（可选）'),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  key: const Key('local-chat-persona-prompt'),
                  controller: _prompt,
                  contextMenuBuilder: buildAppEditableTextContextMenu,
                  minLines: null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: '系统提示词',
                    hintText: '例如：你是一位耐心的英语口语教练……',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    key: const Key('local-chat-persona-save'),
                    onPressed: _valid ? _save : null,
                    child: const Text('保存角色'),
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
