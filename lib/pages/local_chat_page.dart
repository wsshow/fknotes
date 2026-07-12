import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../models/local_chat.dart';
import '../models/local_llm.dart';
import '../services/language_model_service.dart';
import '../services/local_assistant_service.dart';
import '../services/local_chat_prompt_builder.dart';
import '../services/local_chat_store.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/fk_markdown_view.dart';
import 'model_management_page.dart';

class LocalChatPage extends StatefulWidget {
  final String? initialSessionId;

  const LocalChatPage({super.key, this.initialSessionId});

  @override
  State<LocalChatPage> createState() => _LocalChatPageState();
}

class _LocalChatPageState extends State<LocalChatPage> {
  final _store = LocalChatStore.instance;
  final _assistant = LocalAssistantService.instance;
  final _models = LanguageModelService.instance;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  List<LocalChatSession> _sessions = [];
  late LocalChatSession _session;
  bool _loading = true;
  bool _generating = false;
  bool _modelInstalled = false;
  String _modelName = '本地语言模型';
  String? _loadError;
  String? _generationError;
  String? _draftMessageId;
  bool _closed = false;
  bool _autoFollowOutput = true;
  bool _showJumpToBottom = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final sessions = await _store.loadSessions();
      final selectedId = await _models.selectedModelId();
      final model = await _models.inspect(selectedId);
      if (!mounted) return;
      LocalChatSession? initialSession;
      final initialSessionId = widget.initialSessionId;
      if (initialSessionId != null) {
        for (final session in sessions) {
          if (session.id == initialSessionId) {
            initialSession = session;
            break;
          }
        }
      }
      setState(() {
        _sessions = sessions;
        _session =
            initialSession ??
            (sessions.isEmpty ? _store.createSession() : sessions.first);
        _modelName = _models.displayName(selectedId);
        _modelInstalled = model.installed;
        _loading = false;
      });
      _scrollToEnd(force: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _session = _store.createSession();
        _loading = false;
        _loadError = _cleanError(error);
      });
    }
  }

  @override
  void dispose() {
    _closed = true;
    if (_generating) unawaited(_assistant.cancel());
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本地助手',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (!_loading)
            Text(
              _session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '对话记录',
          onPressed: _loading || _generating ? null : _showHistory,
          icon: const Icon(Icons.history_rounded),
        ),
        IconButton(
          tooltip: '角色设定',
          onPressed: _loading || _generating ? null : _editSystemPrompt,
          icon: const Icon(Icons.psychology_alt_outlined),
        ),
        AppAnchoredMenuButton<String>(
          tooltip: '更多对话操作',
          enabled: !_loading && !_generating,
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            if (value == 'new') unawaited(_newConversation());
            if (value == 'delete') unawaited(_deleteConversation());
          },
          actions: const [
            AppMenuAction(
              value: 'new',
              icon: Icons.add_comment_outlined,
              label: '新对话',
            ),
            AppMenuAction(
              value: 'delete',
              icon: Icons.delete_outline_rounded,
              label: '删除当前对话',
              destructive: true,
            ),
          ],
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : Column(
            children: [
              _ModelBar(
                name: _modelName,
                installed: _modelInstalled,
                roleLabel: _roleLabel,
                onTap: _generating ? null : _openModels,
              ),
              Expanded(child: _buildConversationBody()),
              if (_generationError != null)
                _GenerationError(
                  message: _generationError!,
                  onRetry: _canRetry ? _retryLastMessage : null,
                  onClose: () => setState(() => _generationError = null),
                ),
              _Composer(
                controller: _input,
                focusNode: _inputFocus,
                generating: _generating,
                onSend: _send,
                onStop: _stop,
              ),
            ],
          ),
  );

  Widget _buildConversationBody() {
    if (_loadError != null) {
      return _LoadFailure(message: _loadError!, onRetry: _initialize);
    }
    if (_session.messages.isEmpty && !_generating) {
      return _EmptyChat(onSuggestion: _useSuggestion);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleTimelineScroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _session.messages.length,
              itemBuilder: (context, index) {
                final message = _session.messages[index];
                final previous = index == 0
                    ? null
                    : _session.messages[index - 1];
                final startsNewDay =
                    previous == null ||
                    !LocalChatTimeLabel.isSameDay(
                      previous.createdAt,
                      message.createdAt,
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (startsNewDay)
                      _ChatDateDivider(createdAt: message.createdAt),
                    _ChatBubble(
                      message: message,
                      generating: _generating && message.id == _draftMessageId,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 14,
          child: AnimatedScale(
            scale: _showJumpToBottom ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _showJumpToBottom ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !_showJumpToBottom,
                child: FloatingActionButton.small(
                  key: const Key('local-chat-jump-to-bottom'),
                  tooltip: '回到底部',
                  onPressed: _jumpToBottom,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.moss,
                  shape: const CircleBorder(
                    side: BorderSide(color: AppColors.line),
                  ),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _handleTimelineScroll(ScrollNotification notification) {
    final userDriven =
        notification is UserScrollNotification ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null);
    if (!userDriven) return false;
    final followsOutput = LocalChatScrollFollowPolicy.shouldFollow(
      notification.metrics.extentAfter,
    );
    if (followsOutput != _autoFollowOutput ||
        _showJumpToBottom == followsOutput) {
      setState(() {
        _autoFollowOutput = followsOutput;
        _showJumpToBottom = !followsOutput;
      });
    }
    return false;
  }

  void _jumpToBottom() {
    setState(() {
      _autoFollowOutput = true;
      _showJumpToBottom = false;
    });
    _scrollToEnd(force: true);
  }

  String get _roleLabel {
    final prompt = _session.systemPrompt.trim();
    if (prompt.isEmpty) return '无系统角色';
    if (prompt == LocalChatStore.defaultSystemPrompt) return '默认角色';
    return '自定义角色';
  }

  bool get _canRetry {
    if (_generating || _session.messages.isEmpty) return false;
    final last = _session.messages.last;
    if (last.role == LocalChatRole.user) return true;
    return last.status == LocalChatMessageStatus.stopped &&
        _session.messages.length > 1 &&
        _session.messages[_session.messages.length - 2].role ==
            LocalChatRole.user;
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty || _generating) return;
    if (!await _ensureModelInstalled()) return;
    _input.clear();
    final firstUserMessage = !_session.messages.any(
      (message) => message.role == LocalChatRole.user,
    );
    final messages = [
      ..._session.messages,
      _store.createMessage(role: LocalChatRole.user, content: content),
    ];
    _session = _session.copyWith(
      title: firstUserMessage ? _store.titleFrom(content) : _session.title,
      messages: messages,
      updatedAt: DateTime.now(),
    );
    setState(() => _generationError = null);
    await _persist();
    await _generateResponse();
  }

  Future<void> _retryLastMessage() async {
    if (!_canRetry || !await _ensureModelInstalled()) return;
    if (_session.messages.last.role == LocalChatRole.assistant) {
      _session = _session.copyWith(
        messages: _session.messages.sublist(0, _session.messages.length - 1),
        updatedAt: DateTime.now(),
      );
    }
    setState(() => _generationError = null);
    await _generateResponse();
  }

  Future<void> _generateResponse() async {
    final request = LocalChatPromptBuilder.build(
      systemPrompt: _session.systemPrompt,
      messages: _session.messages,
    );
    final draft = _store.createMessage(
      role: LocalChatRole.assistant,
      content: '',
      status: LocalChatMessageStatus.stopped,
    );
    final raw = StringBuffer();
    _session = _session.copyWith(messages: [..._session.messages, draft]);
    if (mounted) {
      setState(() {
        _generating = true;
        _draftMessageId = draft.id;
      });
      _scrollToEnd(force: true);
    }

    var finishStatus = LocalChatMessageStatus.stopped;
    try {
      await _assistant.loadSelectedModel();
      if (_closed) {
        await _assistant.unload();
        return;
      }
      await for (final event in _assistant.generate(request)) {
        switch (event) {
          case LocalLlmTextDelta():
            raw.write(event.text);
            final visible = LocalLlmOutputFilter.visibleText(raw.toString());
            _replaceMessage(draft.id, draft.copyWith(content: visible));
            if (mounted) {
              setState(() {});
              _scrollToEnd();
            }
          case LocalLlmGenerationCompleted():
            finishStatus =
                event.reason == LocalLlmFinishReason.completed ||
                    event.reason == LocalLlmFinishReason.maxTokens
                ? LocalChatMessageStatus.complete
                : LocalChatMessageStatus.stopped;
        }
      }
    } catch (error) {
      _generationError = _cleanError(error);
    } finally {
      final index = _session.messages.indexWhere(
        (message) => message.id == draft.id,
      );
      if (index >= 0) {
        final generated = _session.messages[index];
        if (generated.content.trim().isEmpty) {
          _session = _session.copyWith(
            messages: _session.messages
                .where((message) => message.id != draft.id)
                .toList(),
            updatedAt: DateTime.now(),
          );
        } else {
          _replaceMessage(draft.id, generated.copyWith(status: finishStatus));
          _session = _session.copyWith(updatedAt: DateTime.now());
        }
      }
      await _persist();
      if (mounted) {
        setState(() {
          _generating = false;
          _draftMessageId = null;
        });
        _scrollToEnd();
      }
    }
  }

  void _replaceMessage(String id, LocalChatMessage replacement) {
    _session = _session.copyWith(
      messages: _session.messages
          .map((message) => message.id == id ? replacement : message)
          .toList(growable: false),
    );
  }

  Future<void> _stop() async {
    if (!_generating) return;
    await _assistant.cancel();
  }

  Future<bool> _ensureModelInstalled() async {
    try {
      final selectedId = await _models.selectedModelId();
      var info = await _models.inspect(selectedId);
      if (info.installed) return true;
      if (!mounted) return false;
      final size = _formatModelSize(_models.downloadSizeBytes(selectedId));
      final openManager = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要本地语言模型'),
          content: Text(
            '当前选择的是 ${_models.displayName(selectedId)}，首次使用需下载约 '
            '$size。聊天内容只在本机处理。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('管理模型'),
            ),
          ],
        ),
      );
      if (openManager != true || !mounted) return false;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ModelManagementPage(focusModelId: selectedId),
        ),
      );
      await _refreshModel();
      final currentId = await _models.selectedModelId();
      info = await _models.inspect(currentId);
      return info.installed;
    } catch (error) {
      if (mounted) setState(() => _generationError = _cleanError(error));
      return false;
    }
  }

  Future<void> _refreshModel() async {
    final selectedId = await _models.selectedModelId();
    final info = await _models.inspect(selectedId);
    if (!mounted) return;
    setState(() {
      _modelName = _models.displayName(selectedId);
      _modelInstalled = info.installed;
    });
  }

  Future<void> _openModels() async {
    final selectedId = await _models.selectedModelId();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModelManagementPage(focusModelId: selectedId),
      ),
    );
    await _refreshModel();
  }

  Future<void> _editSystemPrompt() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _SystemPromptSheet(initialValue: _session.systemPrompt),
    );
    if (result == null || !mounted) return;
    _session = _session.copyWith(
      systemPrompt: result.trim(),
      updatedAt: DateTime.now(),
    );
    setState(() {});
    await _persist();
  }

  Future<void> _showHistory() async {
    final persisted = await _store.loadSessions();
    if (!mounted) return;
    _sessions = persisted;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) =>
          _ChatHistorySheet(sessions: _sessions, selectedId: _session.id),
    );
    if (result == null || !mounted) return;
    if (result == _ChatHistorySheet.newConversation) {
      await _newConversation();
      return;
    }
    final selected = _sessions.where((session) => session.id == result);
    if (selected.isEmpty) return;
    setState(() {
      _session = selected.first;
      _generationError = null;
      _autoFollowOutput = true;
      _showJumpToBottom = false;
    });
    _scrollToEnd(force: true);
  }

  Future<void> _newConversation() async {
    if (_session.messages.isEmpty &&
        _session.systemPrompt == LocalChatStore.defaultSystemPrompt) {
      _input.clear();
      _inputFocus.requestFocus();
      return;
    }
    setState(() {
      _session = _store.createSession();
      _generationError = null;
      _autoFollowOutput = true;
      _showJumpToBottom = false;
    });
    _input.clear();
    _inputFocus.requestFocus();
  }

  Future<void> _deleteConversation() async {
    if (_session.messages.isEmpty &&
        !_sessions.any((session) => session.id == _session.id)) {
      await _newConversation();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当前对话？'),
        content: const Text('聊天内容和这个会话的角色设定将无法恢复。'),
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
    await _store.deleteSession(_session.id);
    final sessions = await _store.loadSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _session = sessions.isEmpty ? _store.createSession() : sessions.first;
      _generationError = null;
      _autoFollowOutput = true;
      _showJumpToBottom = false;
    });
  }

  Future<void> _persist() async {
    try {
      await _store.saveSession(_session);
      final index = _sessions.indexWhere((item) => item.id == _session.id);
      if (index < 0) {
        _sessions.insert(0, _session);
      } else {
        _sessions[index] = _session;
      }
      _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error) {
      _generationError = '无法保存聊天记录：${_cleanError(error)}';
      if (mounted) setState(() {});
    }
  }

  void _useSuggestion(String value) {
    _input.text = value;
    _input.selection = TextSelection.collapsed(offset: value.length);
    _inputFocus.requestFocus();
  }

  void _scrollToEnd({bool force = false}) {
    if (!force && !_autoFollowOutput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (!force && !_autoFollowOutput) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  static String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');

  static String _formatModelSize(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(1)} GB'
      : '${(bytes / 1048576).toStringAsFixed(0)} MB';
}

class LocalChatTimeLabel {
  const LocalChatTimeLabel._();

  static bool isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static String date(DateTime value, {DateTime? now}) {
    final today = now ?? DateTime.now();
    if (isSameDay(value, today)) return '今天';
    if (isSameDay(value, today.subtract(const Duration(days: 1)))) {
      return '昨天';
    }
    return value.year == today.year
        ? DateFormat('M月d日').format(value)
        : DateFormat('yyyy年M月d日').format(value);
  }

  static String time(DateTime value) => DateFormat('HH:mm').format(value);
}

class LocalChatScrollFollowPolicy {
  const LocalChatScrollFollowPolicy._();

  static const bottomThreshold = 72.0;

  static bool shouldFollow(double extentAfter) =>
      extentAfter <= bottomThreshold;
}

class _ChatDateDivider extends StatelessWidget {
  final DateTime createdAt;

  const _ChatDateDivider({required this.createdAt});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3, bottom: 15),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            LocalChatTimeLabel.date(createdAt),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

class _ModelBar extends StatelessWidget {
  final String name;
  final bool installed;
  final String roleLabel;
  final VoidCallback? onTap;

  const _ModelBar({
    required this.name,
    required this.installed,
    required this.roleLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$name，${installed ? '已安装' : '未安装'}，$roleLabel',
    onTap: onTap,
    excludeSemantics: true,
    child: Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Icon(
                installed ? Icons.memory_rounded : Icons.download_outlined,
                size: 18,
                color: installed ? AppColors.moss : AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name · ${installed ? '已安装' : '未安装'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  roleLabel,
                  style: const TextStyle(
                    color: AppColors.moss,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyChat extends StatelessWidget {
  final ValueChanged<String> onSuggestion;
  const _EmptyChat({required this.onSuggestion});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(26, 64, 26, 28),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            color: AppColors.softGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.moss,
            size: 29,
          ),
        ),
        const SizedBox(height: 18),
        Text('你想聊什么？', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 7),
        const Text(
          '自由输入任何内容。消息和角色设定只保存在本机。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 26),
        _Suggestion(text: '帮我梳理今天最重要的三件事', onTap: onSuggestion),
        _Suggestion(text: '用通俗的话解释一个复杂概念', onTap: onSuggestion),
        _Suggestion(text: '和我一起完善一个新想法', onTap: onSuggestion),
      ],
    ),
  );
}

class _Suggestion extends StatelessWidget {
  final String text;
  final ValueChanged<String> onTap;
  const _Suggestion({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: OutlinedButton(
      onPressed: () => onTap(text),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        alignment: Alignment.centerLeft,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(text),
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  final LocalChatMessage message;
  final bool generating;
  const _ChatBubble({required this.message, required this.generating});

  @override
  Widget build(BuildContext context) {
    final user = message.role == LocalChatRole.user;
    return Semantics(
      container: true,
      liveRegion: generating,
      label: user
          ? '你的消息'
          : generating
          ? 'AI 正在回复'
          : 'AI 回复',
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .84,
          ),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
          decoration: BoxDecoration(
            color: user ? AppColors.moss : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(user ? 17 : 5),
              bottomRight: Radius.circular(user ? 5 : 17),
            ),
            border: user ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.content.isEmpty && generating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (user)
                SelectableText(
                  message.content,
                  contextMenuBuilder: buildAppEditableTextContextMenu,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.55,
                  ),
                )
              else
                FkMarkdownView(data: message.content, compact: true),
              if (user && message.content.isNotEmpty) ...[
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    LocalChatTimeLabel.time(message.createdAt),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              if (!user && message.content.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      LocalChatTimeLabel.time(message.createdAt),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                    if (message.status == LocalChatMessageStatus.stopped)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text(
                          '已停止',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: '复制回答',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制回答')),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                    ),
                    if (generating)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text(
                          '正在生成…',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool generating;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.generating,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('local-chat-input'),
              controller: controller,
              focusNode: focusNode,
              contextMenuBuilder: buildAppEditableTextContextMenu,
              enabled: !generating,
              minLines: 1,
              maxLines: 6,
              maxLength: 4000,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: '输入消息…',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            key: Key(generating ? 'stop-local-chat' : 'send-local-chat'),
            tooltip: generating ? '停止生成' : '发送',
            onPressed: generating ? onStop : onSend,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.moss,
              foregroundColor: Colors.white,
              minimumSize: const Size(46, 46),
            ),
            icon: Icon(
              generating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    ),
  );
}

class _GenerationError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onClose;
  const _GenerationError({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: AppColors.softCoral,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.coral,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('重试')),
        IconButton(
          tooltip: '关闭提示',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - 56).clamp(0, double.infinity),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.coral),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('重新读取')),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SystemPromptSheet extends StatefulWidget {
  final String initialValue;
  const _SystemPromptSheet({required this.initialValue});

  @override
  State<_SystemPromptSheet> createState() => _SystemPromptSheetState();
}

class _SystemPromptSheetState extends State<_SystemPromptSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        MediaQuery.sizeOf(context).height - keyboardInset - 32;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SizedBox(
            height: availableHeight.clamp(240, 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '角色设定',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                const Text(
                  '系统提示词只对当前对话生效并保存在本机；留空表示不设定角色。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: TextField(
                    key: const Key('local-chat-system-prompt'),
                    controller: _controller,
                    contextMenuBuilder: buildAppEditableTextContextMenu,
                    autofocus: true,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '例如：你是一位耐心的英语口语教练……',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        _controller.text = LocalChatStore.defaultSystemPrompt;
                        _controller.selection = TextSelection.collapsed(
                          offset: _controller.text.length,
                        );
                        setState(() {});
                      },
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('恢复默认'),
                    ),
                    TextButton(onPressed: _dismiss, child: const Text('取消')),
                    FilledButton(
                      onPressed: () => _dismiss(_controller.text),
                      child: const Text('保存设定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHistorySheet extends StatelessWidget {
  static const newConversation = '__new_conversation__';
  final List<LocalChatSession> sessions;
  final String selectedId;
  const _ChatHistorySheet({required this.sessions, required this.selectedId});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '对话记录',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, newConversation),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新对话'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  '还没有保存的对话',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return ListTile(
                    selected: session.id == selectedId,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.chat_bubble_outline_rounded),
                    title: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${session.messages.length} 条消息 · ${_time(session.updatedAt)}',
                    ),
                    trailing: session.id == selectedId
                        ? const Icon(Icons.check_rounded, color: AppColors.moss)
                        : null,
                    onTap: () => Navigator.pop(context, session.id),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );

  static String _time(DateTime value) =>
      '${value.month}/${value.day} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
