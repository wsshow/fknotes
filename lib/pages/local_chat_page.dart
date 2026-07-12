import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../models/local_chat.dart';
import '../models/local_llm.dart';
import '../services/language_model_service.dart';
import '../services/local_assistant_service.dart';
import '../services/local_chat_prompt_builder.dart';
import '../services/local_chat_store.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../services/file_storage_service.dart';
import '../services/realtime_dictation_service.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/fk_markdown_view.dart';
import 'local_chat_roles_page.dart';
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
  final _storage = FileStorageService.instance;
  final _imagePicker = ImagePicker();
  final _dictation = RealtimeDictationService.instance;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  List<LocalChatSession> _sessions = [];
  List<LocalChatPersona> _personas = const [];
  late LocalChatSession _session;
  bool _loading = true;
  bool _generating = false;
  bool _modelInstalled = false;
  LocalLlmCapabilities _modelCapabilities = const LocalLlmCapabilities();
  String _modelName = '本地语言模型';
  String? _loadError;
  String? _generationError;
  String? _draftMessageId;
  bool _closed = false;
  bool _autoFollowOutput = true;
  bool _showJumpToBottom = false;
  final List<LocalChatAttachment> _pendingAttachments = [];
  bool _pickingImages = false;
  bool _chatDictating = false;
  String _dictationBaseText = '';

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_handleDictationChanged);
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
      final personas = await _store.loadPersonas();
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
        _personas = personas;
        _session =
            initialSession ??
            (sessions.isEmpty ? _store.createSession() : sessions.first);
        _modelName = _models.displayName(selectedId);
        _modelInstalled = model.installed;
        _modelCapabilities = _models.capabilities(selectedId);
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
    if (_chatDictating) unawaited(_dictation.cancel());
    _dictation.removeListener(_handleDictationChanged);
    for (final attachment in _pendingAttachments) {
      unawaited(_storage.deleteFile(attachment.filePath));
    }
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
          tooltip: '角色管理',
          onPressed: _loading || _generating ? null : _openPersonaManager,
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
                onModelTap: _generating ? null : _openModels,
                onRoleTap: _generating ? null : _showPersonaSwitcher,
              ),
              Expanded(child: _buildConversationBody()),
              if (_generationError != null)
                _GenerationError(
                  message: _generationError!,
                  onRetry: _canRetry ? _retryLastMessage : null,
                  onClose: () => setState(() => _generationError = null),
                ),
              LocalChatComposer(
                controller: _input,
                focusNode: _inputFocus,
                generating: _generating,
                pendingAttachments: _pendingAttachments,
                imageInputAvailable: _modelCapabilities.imageInput,
                pickingImages: _pickingImages,
                dictating: _chatDictating,
                dictationPreparing:
                    _chatDictating &&
                    _dictation.status == RealtimeDictationStatus.preparing,
                onTakePhoto: _takeChatPhoto,
                onPickImages: _pickChatImages,
                onRemoveAttachment: _removePendingAttachment,
                onToggleDictation: _toggleDictation,
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
    return _currentPersona?.name ?? '通用助手';
  }

  LocalChatPersona? get _currentPersona {
    for (final persona in _personas) {
      if (persona.id == _session.personaId) return persona;
    }
    for (final persona in _personas) {
      if (persona.id == LocalChatPersona.defaultId) return persona;
    }
    return _personas.firstOrNull;
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
    if (_generating) return;
    if (_chatDictating) await _finishDictation();
    if (!mounted) return;
    final content = _input.text.trim();
    if ((content.isEmpty && _pendingAttachments.isEmpty) || _generating) return;
    if (_pendingAttachments.isNotEmpty && !_modelCapabilities.imageInput) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前本地运行时仅支持文字输入；图片已经保留在输入区，请移除或等待多模态运行时')),
      );
      return;
    }
    if (!await _ensureModelInstalled()) return;
    final attachments = List<LocalChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    _input.clear();
    _pendingAttachments.clear();
    final firstUserMessage = !_session.messages.any(
      (message) => message.role == LocalChatRole.user,
    );
    final messages = [
      ..._session.messages,
      _store.createMessage(
        role: LocalChatRole.user,
        content: content,
        attachments: attachments,
      ),
    ];
    _session = _session.copyWith(
      title: firstUserMessage
          ? _store.titleFrom(content.isEmpty ? '图片对话' : content)
          : _session.title,
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
      _modelCapabilities = _models.capabilities(selectedId);
    });
  }

  Future<void> _pickChatImages() =>
      _importChatImages(() => _imagePicker.pickMultiImage());

  Future<void> _takeChatPhoto() => _importChatImages(() async {
    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    return image == null ? const <XFile>[] : [image];
  });

  Future<void> _importChatImages(
    Future<List<XFile>> Function() selectImages,
  ) async {
    if (_generating ||
        _chatDictating ||
        _pickingImages ||
        _pendingAttachments.length >= 4) {
      return;
    }
    setState(() => _pickingImages = true);
    final imported = <LocalChatAttachment>[];
    try {
      final selected = await selectImages();
      final remaining = 4 - _pendingAttachments.length;
      for (final image in selected.take(remaining)) {
        final source = File(image.path);
        if (!await source.exists()) continue;
        final filePath = await _storage.importAssistantImage(source);
        imported.add(
          _store.createImageAttachment(
            filePath: filePath,
            fileName: '${image.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.jpg',
            mimeType: 'image/jpeg',
          ),
        );
      }
      if (!mounted) {
        for (final attachment in imported) {
          await _storage.deleteFile(attachment.filePath);
        }
        return;
      }
      setState(() => _pendingAttachments.addAll(imported));
      if (imported.isNotEmpty && !_modelCapabilities.imageInput) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已保留在输入区；当前模型不支持图片理解，请切换到支持图片的模型')),
        );
      }
    } catch (error) {
      for (final attachment in imported) {
        await _storage.deleteFile(attachment.filePath);
      }
      if (mounted) {
        setState(() => _generationError = _cleanError(error));
      }
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _removePendingAttachment(LocalChatAttachment attachment) async {
    setState(() => _pendingAttachments.remove(attachment));
    await _storage.deleteFile(attachment.filePath);
  }

  Future<void> _toggleDictation() async {
    if (_generating) return;
    if (_chatDictating) {
      await _finishDictation();
      return;
    }
    if (_dictation.isActive) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('其他页面正在使用实时语音输入')));
      return;
    }
    _dictationBaseText = _input.text.trimRight();
    setState(() => _chatDictating = true);
    try {
      if (_assistant.isActive) await _assistant.unload();
      await _dictation.start();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chatDictating = false;
        _generationError = _cleanError(error);
      });
    }
  }

  Future<void> _finishDictation() async {
    if (!_chatDictating) return;
    try {
      if (_dictation.isActive) await _dictation.stop();
      _applyDictationText(_dictation.text);
    } catch (error) {
      if (mounted) setState(() => _generationError = _cleanError(error));
    } finally {
      if (mounted) setState(() => _chatDictating = false);
    }
  }

  void _handleDictationChanged() {
    if (!_chatDictating || !mounted) return;
    _applyDictationText(_dictation.text);
    if (_dictation.status == RealtimeDictationStatus.failed) {
      setState(() {
        _chatDictating = false;
        _generationError = _dictation.errorMessage ?? '语音输入失败';
      });
    } else {
      setState(() {});
    }
  }

  void _applyDictationText(String recognized) {
    final combined = LocalChatVoiceInputText.combine(
      _dictationBaseText,
      recognized,
    );
    _input.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
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

  Future<void> _showPersonaSwitcher() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _PersonaPickerSheet(
        personas: _personas,
        selectedId: _session.personaId,
      ),
    );
    if (result == null || !mounted) return;
    if (result == _PersonaPickerSheet.managePersonas) {
      await _openPersonaManager();
      return;
    }
    final selected = _personas.where((persona) => persona.id == result);
    if (selected.isEmpty) return;
    final persona = selected.first;
    _session = _session.copyWith(
      personaId: persona.id,
      systemPrompt: persona.systemPrompt,
      updatedAt: DateTime.now(),
    );
    setState(() {});
    await _persist();
  }

  Future<void> _openPersonaManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LocalChatRolesPage(selectedPersonaId: _session.personaId),
      ),
    );
    if (!mounted) return;
    final personas = await _store.loadPersonas();
    if (!mounted) return;
    var selectedExists = false;
    for (final persona in personas) {
      if (persona.id == _session.personaId) {
        selectedExists = true;
        break;
      }
    }
    setState(() => _personas = personas);
    if (!selectedExists) {
      final fallback = _currentPersona;
      if (fallback != null) {
        _session = _session.copyWith(
          personaId: fallback.id,
          systemPrompt: fallback.systemPrompt,
          updatedAt: DateTime.now(),
        );
        setState(() {});
        await _persist();
      }
    }
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
    if (_session.messages.isEmpty) {
      _input.clear();
      _inputFocus.requestFocus();
      return;
    }
    final persona = _currentPersona;
    setState(() {
      _session = _store.createSession(
        personaId: persona?.id ?? LocalChatPersona.defaultId,
        systemPrompt:
            persona?.systemPrompt ?? LocalChatPersona.defaultSystemPrompt,
      );
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

class LocalChatVoiceInputText {
  const LocalChatVoiceInputText._();

  static String combine(String existing, String recognized) {
    final base = existing.trimRight();
    final speech = recognized.trim();
    final separator = base.isEmpty || speech.isEmpty ? '' : ' ';
    return '$base$separator$speech';
  }
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
  final VoidCallback? onModelTap;
  final VoidCallback? onRoleTap;

  const _ModelBar({
    required this.name,
    required this.installed,
    required this.roleLabel,
    required this.onModelTap,
    required this.onRoleTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: onModelTap != null,
    label: '$name，${installed ? '已安装' : '未安装'}，$roleLabel',
    onTap: onModelTap,
    child: Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onModelTap,
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
              Material(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  key: const Key('local-chat-persona-switcher'),
                  onTap: onRoleTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 92),
                          child: Text(
                            roleLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.moss,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: AppColors.moss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: onModelTap == null ? AppColors.line : AppColors.muted,
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
          padding: EdgeInsets.fromLTRB(14, 11, 14, user ? 10 : 8),
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
              if (message.attachments.isNotEmpty) ...[
                _ChatMessageAttachments(attachments: message.attachments),
                if (message.content.isNotEmpty) const SizedBox(height: 9),
              ],
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
                const SizedBox(height: 3),
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
                    if (message.status == LocalChatMessageStatus.stopped) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '已停止',
                        style: TextStyle(color: AppColors.muted, fontSize: 10),
                      ),
                    ],
                    const SizedBox(width: 6),
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
                      style: IconButton.styleFrom(
                        minimumSize: const Size(30, 30),
                        maximumSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: 17,
                        color: AppColors.muted,
                      ),
                    ),
                    if (generating)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
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

class LocalChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool generating;
  final List<LocalChatAttachment> pendingAttachments;
  final bool imageInputAvailable;
  final bool pickingImages;
  final bool dictating;
  final bool dictationPreparing;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickImages;
  final ValueChanged<LocalChatAttachment> onRemoveAttachment;
  final VoidCallback onToggleDictation;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const LocalChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.generating,
    required this.pendingAttachments,
    required this.imageInputAvailable,
    required this.pickingImages,
    required this.dictating,
    required this.dictationPreparing,
    required this.onTakePhoto,
    required this.onPickImages,
    required this.onRemoveAttachment,
    required this.onToggleDictation,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasContent =
                    value.text.trim().isNotEmpty ||
                    pendingAttachments.isNotEmpty;
                final canAddImage =
                    !generating &&
                    !dictating &&
                    !pickingImages &&
                    pendingAttachments.length < 4;
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      pendingAttachments.isEmpty ? 28 : 24,
                    ),
                    border: Border.all(color: AppColors.line),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: .08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pendingAttachments.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: SizedBox(
                            height: 92,
                            child: ListView.separated(
                              key: const Key('local-chat-image-strip'),
                              scrollDirection: Axis.horizontal,
                              itemCount:
                                  pendingAttachments.length +
                                  (canAddImage ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 9),
                              itemBuilder: (context, index) {
                                if (index == pendingAttachments.length) {
                                  return _AddPendingImage(
                                    loading: pickingImages,
                                    onPressed: onPickImages,
                                  );
                                }
                                final attachment = pendingAttachments[index];
                                return _PendingImage(
                                  attachment: attachment,
                                  onPreview: () => _showChatImagePreview(
                                    context,
                                    pendingAttachments,
                                    index,
                                  ),
                                  onRemove: () =>
                                      onRemoveAttachment(attachment),
                                );
                              },
                            ),
                          ),
                        ),
                        if (!imageInputAvailable)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(14, 0, 14, 9),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '当前模型不支持图片理解，请切换模型后发送',
                                style: TextStyle(
                                  color: AppColors.coral,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        const Divider(height: 1, color: AppColors.line),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              key: const Key('local-chat-take-photo'),
                              tooltip: imageInputAvailable
                                  ? '拍照'
                                  : '拍照（当前模型不支持图片）',
                              onPressed: canAddImage ? onTakePhoto : null,
                              style: IconButton.styleFrom(
                                fixedSize: const Size(44, 44),
                                foregroundColor: AppColors.ink,
                              ),
                              icon: pickingImages
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.photo_camera_outlined,
                                      size: 25,
                                    ),
                            ),
                            Expanded(
                              child: TextField(
                                key: const Key('local-chat-input'),
                                controller: controller,
                                focusNode: focusNode,
                                contextMenuBuilder:
                                    buildAppEditableTextContextMenu,
                                enabled: !generating && !dictating,
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
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: dictating ? '正在听写…' : '发消息或使用语音…',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (generating)
                              _ChatComposerAction(
                                key: const Key('stop-local-chat'),
                                tooltip: '停止生成',
                                onPressed: onStop,
                                filled: true,
                                icon: Icons.stop_rounded,
                              )
                            else if (dictating || dictationPreparing)
                              _ChatComposerAction(
                                key: const Key('local-chat-voice-input'),
                                tooltip: '完成语音输入',
                                onPressed: onToggleDictation,
                                active: true,
                                icon: dictationPreparing
                                    ? null
                                    : Icons.stop_rounded,
                                loading: dictationPreparing,
                              )
                            else if (hasContent)
                              _ChatComposerAction(
                                key: const Key('send-local-chat'),
                                tooltip: '发送',
                                onPressed: onSend,
                                filled: true,
                                icon: Icons.arrow_upward_rounded,
                              )
                            else ...[
                              _ChatComposerAction(
                                key: const Key('local-chat-voice-input'),
                                tooltip: '语音输入',
                                onPressed: onToggleDictation,
                                icon: Icons.graphic_eq_rounded,
                              ),
                              const SizedBox(width: 5),
                              _ChatComposerAction(
                                key: const Key('local-chat-add-image'),
                                tooltip: imageInputAvailable
                                    ? '添加图片'
                                    : '添加图片（当前模型不支持）',
                                onPressed: canAddImage ? onPickImages : null,
                                icon: Icons.add_rounded,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (dictating) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  const SizedBox(width: 52),
                  Expanded(
                    child: Text(
                      dictationPreparing ? '正在准备离线语音识别…' : '正在听写，点击麦克风完成',
                      style: const TextStyle(
                        color: AppColors.coral,
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

class _ChatComposerAction extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool active;
  final bool loading;

  const _ChatComposerAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.filled = false,
    this.active = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      backgroundColor: filled
          ? AppColors.moss
          : active
          ? AppColors.softCoral
          : AppColors.surface,
      foregroundColor: filled
          ? Colors.white
          : active
          ? AppColors.coral
          : AppColors.ink,
      disabledBackgroundColor: AppColors.softBlue,
      disabledForegroundColor: AppColors.muted,
      side: filled
          ? BorderSide.none
          : BorderSide(color: active ? AppColors.coral : AppColors.line),
    ),
    icon: loading
        ? const SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 24),
  );
}

class _PendingImage extends StatelessWidget {
  final LocalChatAttachment attachment;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  const _PendingImage({
    required this.attachment,
    required this.onPreview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            button: true,
            label: '预览图片',
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('pending-chat-image-${attachment.id}'),
                onTap: onPreview,
                child: Image.file(
                  File(
                    FileStorageService.instance.absolutePath(
                      attachment.filePath,
                    ),
                  ),
                  fit: BoxFit.cover,
                  cacheWidth: 276,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.softBlue,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: Tooltip(
            message: '移除图片',
            child: Semantics(
              button: true,
              label: '移除图片',
              child: Material(
                color: AppColors.ink.withValues(alpha: .72),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('remove-chat-image-${attachment.id}'),
                  onTap: onRemove,
                  child: const SizedBox.square(
                    dimension: 27,
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AddPendingImage extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _AddPendingImage({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Tooltip(
      message: '继续添加图片',
      child: Material(
        color: AppColors.softBlue,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('local-chat-image-strip-add'),
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: AppColors.muted,
                    size: 34,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _ChatMessageAttachments extends StatelessWidget {
  final List<LocalChatAttachment> attachments;

  const _ChatMessageAttachments({required this.attachments});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 132,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      shrinkWrap: true,
      itemCount: attachments.length,
      separatorBuilder: (_, _) => const SizedBox(width: 7),
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return Semantics(
          button: true,
          label: '预览图片 ${index + 1}',
          child: InkWell(
            key: Key('sent-chat-image-${attachment.id}'),
            onTap: () => _showChatImagePreview(context, attachments, index),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(
                  FileStorageService.instance.absolutePath(attachment.filePath),
                ),
                width: 176,
                height: 132,
                fit: BoxFit.cover,
                cacheWidth: 520,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 176,
                  child: ColoredBox(
                    color: AppColors.softBlue,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _showChatImagePreview(
  BuildContext context,
  List<LocalChatAttachment> attachments,
  int initialIndex,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ChatImagePreviewPage(
      attachments: List.unmodifiable(attachments),
      initialIndex: initialIndex,
    ),
  ),
);

class _ChatImagePreviewPage extends StatefulWidget {
  final List<LocalChatAttachment> attachments;
  final int initialIndex;

  const _ChatImagePreviewPage({
    required this.attachments,
    required this.initialIndex,
  });

  @override
  State<_ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState extends State<_ChatImagePreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('local-chat-image-preview'),
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: '关闭预览',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(
        '${_currentIndex + 1} / ${widget.attachments.length}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
    ),
    body: PageView.builder(
      key: const Key('local-chat-image-preview-pages'),
      controller: _pageController,
      itemCount: widget.attachments.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (context, index) {
        final attachment = widget.attachments[index];
        return InteractiveViewer(
          key: Key('local-chat-image-zoom-${attachment.id}'),
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(72),
          child: Center(
            child: Image.file(
              File(
                FileStorageService.instance.absolutePath(attachment.filePath),
              ),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text('图片无法打开', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        );
      },
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

class _PersonaPickerSheet extends StatelessWidget {
  static const managePersonas = '__manage_personas__';
  final List<LocalChatPersona> personas;
  final String selectedId;

  const _PersonaPickerSheet({required this.personas, required this.selectedId});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '切换角色',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, managePersonas),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('管理'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: personas.length,
              itemBuilder: (context, index) {
                final persona = personas[index];
                final selected = persona.id == selectedId;
                return ListTile(
                  key: Key('local-chat-persona-${persona.id}'),
                  selected: selected,
                  leading: CircleAvatar(
                    backgroundColor: selected
                        ? AppColors.moss
                        : AppColors.softCoral,
                    foregroundColor: selected ? Colors.white : AppColors.coral,
                    child: const Icon(Icons.psychology_alt_outlined),
                  ),
                  title: Text(persona.name),
                  subtitle: persona.description.isEmpty
                      ? null
                      : Text(
                          persona.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: AppColors.moss)
                      : null,
                  onTap: () => Navigator.pop(context, persona.id),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
