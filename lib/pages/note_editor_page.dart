import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../debug/app_diagnostics.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../models/local_chat.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/editor_draft_recovery_service.dart';
import '../services/language_model_service.dart';
import '../services/local_chat_note_context_builder.dart';
import '../services/local_model_manager.dart';
import '../services/kokoro_tts_model_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/realtime_dictation_service.dart';
import '../services/streaming_speech_model_service.dart';
import '../services/video_import_service.dart';
import '../utils/markdown_text.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/note_assistant_sheet.dart';
import '../widgets/note_block_editor.dart';
import '../widgets/note_card.dart';
import '../widgets/realtime_dictation_provider_badge.dart';
import 'media_detail_page.dart';
import 'local_chat_page.dart';
import 'model_management_page.dart';
import 'record_audio_page.dart';

enum _EditorAutosaveState { enabled, pending, saving, saved, failed }

class NoteEditorPage extends StatefulWidget {
  final NoteEntry? existingEntry;
  final List<String> initialImportJobIds;
  final List<String> initialVideoJobIds;

  static Future<void> openById(BuildContext context, int noteId) async {
    final entry = context.read<NoteProvider>().getEntryById(noteId);
    if (entry == null || entry.isDeleted) {
      AppFeedback.show(context, context.l10n.sourceNoteUnavailable);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
  }

  const NoteEditorPage({
    super.key,
    this.existingEntry,
    this.initialImportJobIds = const [],
    this.initialVideoJobIds = const [],
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _title;
  late final TextEditingController _content;
  String? _richContent;
  late String _lastTitleText;
  late String _lastContentText;
  GlobalKey<NoteBlockEditorState> _blockEditorKey =
      GlobalKey<NoteBlockEditorState>();
  late List<String> _tags;
  late bool _favorite;
  late bool _pinned;
  late List<NoteAttachment> _attachments;
  final List<NoteAttachment> _removedAttachments = [];
  final _storage = FileStorageService.instance;
  final _draftRecovery = EditorDraftRecoveryService.instance;
  final _dictation = RealtimeDictationService.instance;
  final _readAloud = NoteReadAloudService.instance;
  late final Set<String> _importJobIds;
  NoteProvider? _provider;
  NoteEntry? _entry;
  Timer? _autosave;
  Timer? _recoverySave;
  bool _changed = false;
  bool _saving = false;
  bool _autosaveFailed = false;
  bool _saveAgain = false;
  bool _disposing = false;
  bool _importing = false;
  bool _dictationAnchored = false;
  String _dictationInsertedText = '';
  bool _recoveringDictationFailure = false;
  bool _dictationOperationPending = false;
  bool _showDictationDiagnostics = false;
  bool _dictationDiagnosticsCollapsed = false;
  double _dictationDiagnosticsTop = 72;
  double _dictationDiagnosticsLeft = 12;
  double _dictationDiagnosticsWidth = 400;
  double _dictationDiagnosticsHeight = 380;

  bool get _isEditing => _entry != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final entry = widget.existingEntry;
    _entry = entry;
    _importJobIds = {
      ...widget.initialImportJobIds,
      ...widget.initialVideoJobIds,
    };
    _title = TextEditingController(text: entry?.title ?? '');
    _content = TextEditingController(text: entry?.content ?? '');
    _richContent = entry?.richContent;
    _lastTitleText = _title.text;
    _lastContentText = _content.text;
    _tags = [...?entry?.tags];
    _favorite = entry?.isFavorite ?? false;
    _pinned = entry?.isPinned ?? false;
    _attachments = [...?entry?.allAttachments];
    _title.addListener(_onTitleChanged);
    _content.addListener(_onContentChanged);
    _dictation.addListener(_handleDictationChanged);
    _readAloud.addListener(_handleReadAloudChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecoveryDraft());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<NoteProvider>();
    if (identical(_provider, provider)) return;
    _provider?.removeListener(_handleProviderChanged);
    _provider = provider..addListener(_handleProviderChanged);
    final noteId = _entry?.id;
    if (noteId != null) {
      _importJobIds.addAll(
        provider.attachmentImportsForNote(noteId).map((job) => job.id),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleProviderChanged(),
    );
  }

  void _onTitleChanged() {
    if (_title.text == _lastTitleText) return;
    _lastTitleText = _title.text;
    _markChanged();
  }

  void _onContentChanged() {
    if (_content.text == _lastContentText) return;
    _lastContentText = _content.text;
    _markChanged();
  }

  void _onRichContentChanged(String value) {
    if (_richContent == value) return;
    _richContent = value;
    _markChanged();
    if (_dictationAnchored &&
        _dictationInsertedText != _dictation.committedText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_dictationAnchored) return;
        _insertCommittedDictation(_dictation.committedText);
      });
    }
  }

  void _markChanged() {
    if (_disposing) {
      _changed = true;
      _autosaveFailed = false;
      return;
    }
    if ((!_changed || _autosaveFailed) && mounted) {
      setState(() {
        _changed = true;
        _autosaveFailed = false;
      });
    } else {
      _changed = true;
      _autosaveFailed = false;
    }
    _scheduleAutosave();
    _queueRecoveryDraft();
  }

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 700), _persist);
  }

  @override
  void dispose() {
    _disposing = true;
    _autosave?.cancel();
    _recoverySave?.cancel();
    if (_changed) _queueRecoveryDraft(flushEditor: true);
    WidgetsBinding.instance.removeObserver(this);
    _provider?.removeListener(_handleProviderChanged);
    _dictation.removeListener(_handleDictationChanged);
    _readAloud.removeListener(_handleReadAloudChanged);
    if (_readAloud.status != ReadAloudStatus.idle) {
      unawaited(_readAloud.stop());
    }
    if (_dictation.isActive) unawaited(_dictation.cancel());
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _handleDictationChanged() {
    if (!mounted) return;
    if (_dictation.status == RealtimeDictationStatus.failed &&
        _dictationAnchored &&
        !_dictationOperationPending &&
        !_recoveringDictationFailure) {
      _recoveringDictationFailure = true;
      unawaited(_recoverFromDictationFailure());
      return;
    }
    if (_dictationAnchored) {
      _insertCommittedDictation(_dictation.committedText);
    }
    setState(() {});
  }

  void _handleReadAloudChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleReadAloud() async {
    if (_readAloud.isActive || _readAloud.status == ReadAloudStatus.failed) {
      await _readAloud.stop();
      return;
    }
    final model = await KokoroTtsModelService.instance.inspect();
    if (!model.installed) {
      if (!mounted) return;
      final openModels = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.offlineReadAloudModelRequired),
          content: Text(context.l10n.readAloudModelDownloadDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.maybeLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.manageModels),
            ),
          ],
        ),
      );
      if (openModels == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ModelManagementPage(
              focusModelId: KokoroTtsModelService.modelId,
            ),
          ),
        );
      }
      return;
    }
    final text = [
      _title.text.trim(),
      MarkdownText.toPlainText(_content.text).trim(),
    ].where((part) => part.isNotEmpty).join('。');
    try {
      await _readAloud.speak(text);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
          context,
          _readAloud.errorMessage ?? context.l10n.noteReadAloudFailed,
        );
      }
    }
  }

  void _insertCommittedDictation(String committed) {
    if (committed == _dictationInsertedText) return;
    if (!committed.startsWith(_dictationInsertedText)) {
      // Committed recognition is expected to grow monotonically. If a native
      // runtime ever revises it, wait for the final stop result rather than
      // duplicating or overwriting text the user may be editing manually.
      return;
    }
    final addition = committed.substring(_dictationInsertedText.length);
    if (addition.trim().isEmpty) {
      _dictationInsertedText = committed;
      return;
    }
    final inserted =
        _blockEditorKey.currentState?.insertDictationTextAtCaret(addition) ??
        false;
    if (inserted) _dictationInsertedText = committed;
  }

  Future<void> _recoverFromDictationFailure() async {
    final message =
        _dictation.errorMessage ?? context.l10n.liveDictationIncomplete;
    _dictationAnchored = false;
    _dictationInsertedText = '';
    await _dictation.cancel();
    _recoveringDictationFailure = false;
    if (!mounted) return;
    setState(() {});
    AppFeedback.error(context, message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _dictation.status == RealtimeDictationStatus.listening) {
      unawaited(_cancelDictation());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_saveBeforeBackground());
    }
  }

  Future<void> _checkRecoveryDraft() async {
    final noteId = widget.existingEntry?.id;
    final draft = await _draftRecovery.load(noteId);
    if (!mounted) return;
    if (draft == null) return;
    final entry = widget.existingEntry;
    final stale =
        entry != null &&
        (draft.matchesEntry(entry) || !draft.savedAt.isAfter(entry.updatedAt));
    if (stale || (entry == null && draft.isBlank)) {
      await _draftRecovery.clear(noteId);
      return;
    }
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.unsavedDraftFound),
        content: Text(context.l10n.unsavedDraftDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.discardDraft),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.restore),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restore == true) {
      _applyRecoveryDraft(draft);
      _queueRecoveryDraft();
    } else {
      await _draftRecovery.clear(noteId);
    }
  }

  void _applyRecoveryDraft(EditorRecoveryDraft draft) {
    _title.removeListener(_onTitleChanged);
    _content.removeListener(_onContentChanged);
    _title.text = draft.title;
    _content.text = draft.content;
    _lastTitleText = draft.title;
    _lastContentText = draft.content;
    _title.addListener(_onTitleChanged);
    _content.addListener(_onContentChanged);
    setState(() {
      _richContent = draft.richContent;
      _tags = [...draft.tags];
      _favorite = draft.isFavorite;
      _pinned = draft.isPinned;
      _attachments = [...draft.attachments];
      _removedAttachments
        ..clear()
        ..addAll(draft.removedAttachments);
      _blockEditorKey = GlobalKey<NoteBlockEditorState>();
      _changed = true;
    });
    _scheduleAutosave();
  }

  EditorRecoveryDraft _recoverySnapshot() => EditorRecoveryDraft(
    noteId: _entry?.id,
    baseUpdatedAt: _entry?.updatedAt,
    savedAt: DateTime.now(),
    title: _title.text,
    content: _content.text,
    richContent: _richContent,
    tags: [..._tags],
    isFavorite: _favorite,
    isPinned: _pinned,
    attachments: _orderedAttachments,
    removedAttachments: [..._removedAttachments],
  );

  void _queueRecoveryDraft({bool flushEditor = false}) {
    if (!_changed) return;
    _recoverySave?.cancel();
    if (!flushEditor) {
      _recoverySave = Timer(
        const Duration(milliseconds: 180),
        () => _writeRecoveryDraft(flushEditor: false),
      );
      return;
    }
    _writeRecoveryDraft(flushEditor: true);
  }

  void _writeRecoveryDraft({required bool flushEditor}) {
    _recoverySave = null;
    if (!_changed) return;
    if (flushEditor) {
      _richContent =
          _blockEditorKey.currentState?.flushPendingChanges() ?? _richContent;
    }
    final draft = _recoverySnapshot();
    unawaited(
      _draftRecovery.save(draft).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (kDebugMode) {
          AppDiagnostics.error(
            AppLogCategory.editor,
            'editor_recovery_draft_save_failed',
            data: {'noteId': widget.existingEntry?.id},
            error: error,
            stackTrace: stackTrace,
            traceId: widget.existingEntry?.id == null
                ? 'note-new'
                : 'note-${widget.existingEntry!.id}',
          );
        }
      }),
    );
  }

  Future<void> _saveBeforeBackground() async {
    if (!_changed || !mounted) return;
    _autosave?.cancel();
    _recoverySave?.cancel();
    _recoverySave = null;
    _richContent =
        _blockEditorKey.currentState?.flushPendingChanges() ?? _richContent;
    final draft = _recoverySnapshot();
    try {
      await _draftRecovery.save(draft);
      if (mounted) await _persist(showError: false);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.editor,
          'editor_background_save_failed',
          data: {'noteId': widget.existingEntry?.id},
          error: error,
          stackTrace: stackTrace,
          traceId: widget.existingEntry?.id == null
              ? 'note-new'
              : 'note-${widget.existingEntry!.id}',
        );
      }
    }
  }

  Future<void> _toggleDictation() async {
    if (_dictation.status == RealtimeDictationStatus.listening) {
      await _stopDictation();
      return;
    }
    if (_dictation.isActive) return;
    final installed = await StreamingSpeechModelService.instance.inspect();
    if (!installed.installed) {
      if (!mounted) return;
      final definition = LocalModelManager.instance.modelOf(installed.modelId);
      final downloadSize =
          '${(definition.downloadSizeBytes / 1048576).toStringAsFixed(1)} MB';
      final openModels = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.liveSpeechModelRequired),
          content: Text(
            context.l10n.liveSpeechModelDownloadDescription(
              localizedModelName(context.l10n, definition),
              downloadSize,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.maybeLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.manageModels),
            ),
          ],
        ),
      );
      if (openModels == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ModelManagementPage(focusModelId: installed.modelId),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final anchored =
        _blockEditorKey.currentState?.prepareDictationInsertion() ?? false;
    if (!anchored) {
      AppFeedback.show(context, context.l10n.placeCursorInText);
      return;
    }
    _dictationAnchored = true;
    _dictationInsertedText = '';
    _dictationOperationPending = true;
    try {
      await _dictation.start();
      HapticFeedback.mediumImpact();
    } catch (_) {
      _dictationAnchored = false;
      _dictationInsertedText = '';
      if (mounted) {
        AppFeedback.error(
          context,
          _dictation.errorMessage ?? context.l10n.liveDictationStartFailed,
        );
      }
    } finally {
      _dictationOperationPending = false;
    }
  }

  Future<void> _openLocalAssistant() async {
    try {
      _richContent =
          _blockEditorKey.currentState?.flushPendingChanges() ?? _richContent;
      final editor = _blockEditorKey.currentState;
      final anchor = editor?.captureAssistantContext();
      final scopes = <NoteAssistantScope>{NoteAssistantScope.fullNote};
      if (anchor != null) {
        scopes.add(NoteAssistantScope.currentBlock);
      }
      if (anchor?.hasSelection == true) {
        scopes.add(NoteAssistantScope.selection);
      }
      final initialScope = anchor?.hasSelection == true
          ? NoteAssistantScope.selection
          : anchor?.currentBlockContent.trim().isNotEmpty == true
          ? NoteAssistantScope.currentBlock
          : NoteAssistantScope.fullNote;
      final invocation = await showNoteAssistantTaskSheet(
        context,
        availableScopes: scopes,
        initialScope: initialScope,
      );
      if (invocation == null || !mounted || anchor == null) return;

      if (invocation.opensChat) {
        await _openNoteChat(anchor: anchor, scope: invocation.scope);
        return;
      }

      final models = LanguageModelService.instance;
      final selectedId = await models.selectedModelId();
      final installed = await models.inspect(selectedId);
      if (!mounted) return;
      if (!installed.installed) {
        final downloadSize =
            '${(models.downloadSizeBytes(selectedId) / 1073741824).toStringAsFixed(1)} GB';
        final openModels = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.localLanguageModelRequired),
            content: Text(
              context.l10n.localLanguageModelDownloadDescription(
                localizedModelName(
                  context.l10n,
                  LocalModelManager.instance.modelOf(selectedId),
                ),
                downloadSize,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.maybeLater),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.manageModels),
              ),
            ],
          ),
        );
        if (openModels == true && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ModelManagementPage(focusModelId: selectedId),
            ),
          );
          if (!mounted) return;
          final currentModelId = await models.selectedModelId();
          final currentModel = await models.inspect(currentModelId);
          if (!mounted || !currentModel.installed) return;
        } else {
          return;
        }
      }

      final sourceContent = switch (invocation.scope) {
        NoteAssistantScope.selection => anchor.selectedText,
        NoteAssistantScope.currentBlock => anchor.currentBlockContent,
        NoteAssistantScope.fullNote => _content.text,
      };
      final placements = invocation.scope == NoteAssistantScope.fullNote
          ? const {
              NoteAssistantPlacement.replace,
              NoteAssistantPlacement.append,
            }
          : NoteAssistantPlacement.values.toSet();
      final generated = await showModalBottomSheet<NoteAssistantResult>(
        context: context,
        isScrollControlled: true,
        builder: (context) => NoteAssistantResultSheet(
          action: invocation.action,
          scope: invocation.scope,
          title: _title.text,
          content: sourceContent,
          languageCode: Localizations.localeOf(context).languageCode,
          placements: placements,
        ),
      );
      if (generated == null || !mounted) return;
      final inserted =
          _blockEditorKey.currentState?.applyAssistantResult(
            anchor: anchor,
            scope: invocation.scope,
            placement: generated.placement,
            heading: _assistantResultHeading(context, invocation.action),
            text: generated.text,
          ) ??
          false;
      if (inserted) {
        final message = switch (generated.placement) {
          NoteAssistantPlacement.replace =>
            context.l10n.assistantReplacedContent,
          NoteAssistantPlacement.insertBelow =>
            context.l10n.assistantInsertedBelow,
          NoteAssistantPlacement.append => context.l10n.assistantAppended,
        };
        AppFeedback.success(context, message);
      } else {
        AppFeedback.show(context, context.l10n.noteChangedRetryAssistant);
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        context.l10n.assistantLaunchFailed(error.toString()),
      );
    }
  }

  Future<void> _openNoteChat({
    required NoteAssistantEditorContext anchor,
    required NoteAssistantScope scope,
  }) async {
    final sourceContent = switch (scope) {
      NoteAssistantScope.selection => anchor.selectedText,
      NoteAssistantScope.currentBlock => anchor.currentBlockContent,
      NoteAssistantScope.fullNote => _content.text,
    };
    if (_title.text.trim().isEmpty && sourceContent.trim().isEmpty) {
      AppFeedback.show(context, context.l10n.chatNoteEmpty);
      return;
    }
    if (!await _persist() || !mounted) return;
    final entry = _entry;
    if (entry?.id == null) {
      AppFeedback.show(context, context.l10n.chatNoteEmpty);
      return;
    }
    final noteContext = LocalChatNoteContextBuilder.fit([
      LocalChatNoteContextBuilder.fromNote(
        entry!,
        untitledLabel: context.l10n.untitled,
        scope: switch (scope) {
          NoteAssistantScope.selection => LocalChatNoteScope.selection,
          NoteAssistantScope.currentBlock => LocalChatNoteScope.currentBlock,
          NoteAssistantScope.fullNote => LocalChatNoteScope.fullNote,
        },
        content: sourceContent,
      ),
    ]).single;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalChatPage(
          initialNoteContext: noteContext,
          onOpenNote: (source) async {
            if (!mounted) return;
            if (source.noteId == _entry?.id) {
              Navigator.pop(context);
              return;
            }
            await NoteEditorPage.openById(context, source.noteId);
          },
          onWriteBack: (source, text, placement) async {
            if (!mounted || source.noteId != _entry?.id) return false;
            final inserted =
                _blockEditorKey.currentState?.applyAssistantResult(
                  anchor: anchor,
                  scope: scope,
                  placement: placement,
                  text: text,
                  heading: context.l10n.assistantChatResultHeading,
                ) ??
                false;
            if (!inserted) return false;
            return _persist(showError: false);
          },
        ),
      ),
    );
  }

  Future<void> _stopDictation() async {
    _dictationOperationPending = true;
    try {
      final result = await _dictation.stop();
      _finalizeCommittedDictation(result);
      _dictationAnchored = false;
      _dictationInsertedText = '';
      HapticFeedback.mediumImpact();
    } catch (_) {
      _dictationAnchored = false;
      _dictationInsertedText = '';
      if (mounted) {
        AppFeedback.error(
          context,
          _dictation.errorMessage ?? context.l10n.liveDictationIncomplete,
        );
      }
    } finally {
      _dictationOperationPending = false;
    }
  }

  void _finalizeCommittedDictation(String result) {
    if (result.startsWith(_dictationInsertedText)) {
      _insertCommittedDictation(result);
      return;
    }
    final replaced =
        _blockEditorKey.currentState?.replaceDictationTextBeforeCaret(
          previous: _dictationInsertedText,
          replacement: result,
        ) ??
        false;
    if (replaced) _dictationInsertedText = result;
  }

  Future<void> _cancelDictation() async {
    await _dictation.cancel();
    _dictationAnchored = false;
    _dictationInsertedText = '';
    HapticFeedback.selectionClick();
  }

  void _handleProviderChanged() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;
    final noteId = _entry?.id;
    if (noteId != null) {
      _importJobIds.addAll(
        provider.attachmentImportsForNote(noteId).map((job) => job.id),
      );
    }
    final jobsToDismiss = <String>[];
    var changed = _importJobIds.isNotEmpty;
    for (final jobId in _importJobIds.toList()) {
      final job = provider.attachmentImportJob(jobId);
      if (job == null || job.status == AttachmentImportStatus.canceled) {
        _importJobIds.remove(jobId);
        jobsToDismiss.add(jobId);
        changed = true;
        continue;
      }
      if (!job.committed || job.filePath == null || job.noteId == null) {
        continue;
      }
      final refreshed = provider.getEntryById(job.noteId!);
      final imported = refreshed?.allAttachments
          .where((item) => item.filePath == job.filePath)
          .firstOrNull;
      if (imported != null &&
          !_attachments.any((item) => item.filePath == imported.filePath)) {
        _attachments.add(imported);
        _entry = (_entry ?? refreshed)!.copyWith(attachments: _attachments);
      }
      _importJobIds.remove(jobId);
      jobsToDismiss.add(jobId);
      changed = true;
    }
    if (changed) setState(() {});
    if (jobsToDismiss.isNotEmpty) {
      scheduleMicrotask(() {
        for (final jobId in jobsToDismiss) {
          provider.acknowledgeAttachmentImport(jobId);
        }
      });
    }
  }

  Future<bool> _persist({bool showError = true}) async {
    if (_saving) {
      _saveAgain = true;
      return false;
    }
    _richContent =
        _blockEditorKey.currentState?.flushPendingChanges() ?? _richContent;
    final title = _title.text.trim();
    final content = _content.text;
    if (_entry == null &&
        title.isEmpty &&
        content.trim().isEmpty &&
        _attachments.isEmpty) {
      if (mounted) {
        setState(() {
          _changed = false;
          _autosaveFailed = false;
        });
      } else {
        _changed = false;
        _autosaveFailed = false;
      }
      await _clearRecoveryDrafts();
      return true;
    }
    if (mounted) {
      setState(() {
        _saving = true;
        _autosaveFailed = false;
      });
    }
    final provider = _provider ?? context.read<NoteProvider>();
    final now = DateTime.now();
    var success = false;
    try {
      if (_entry != null) {
        final updated = _entry!.copyWith(
          type: _attachments.isEmpty ? NoteType.text : _attachments.first.type,
          title: title,
          content: content,
          richContent: _richContent,
          tags: _tags,
          isFavorite: _favorite,
          isPinned: _pinned,
          updatedAt: now,
          attachments: _orderedAttachments,
        );
        await provider.updateEntry(updated);
        _entry = updated;
      } else {
        final created = NoteEntry(
          type: _attachments.isEmpty ? NoteType.text : _attachments.first.type,
          title: title,
          content: content,
          richContent: _richContent,
          tags: _tags,
          isFavorite: _favorite,
          isPinned: _pinned,
          createdAt: now,
          updatedAt: now,
          attachments: _orderedAttachments,
        );
        final id = await provider.addEntry(created);
        _entry = created.copyWith(id: id);
      }
      _changed = false;
      for (final attachment in _removedAttachments) {
        await _storage.deleteFile(attachment.filePath);
        await _storage.deleteFile(attachment.thumbnailPath);
      }
      _removedAttachments.clear();
      await _clearRecoveryDrafts();
      _autosaveFailed = false;
      success = true;
    } catch (error) {
      _changed = true;
      _autosaveFailed = true;
      if (showError && mounted) {
        AppFeedback.error(
          context,
          context.l10n.autosaveFailed(error.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (_saveAgain) {
      _saveAgain = false;
      return _persist(showError: showError);
    }
    return success;
  }

  _EditorAutosaveState get _autosaveState {
    if (_saving) return _EditorAutosaveState.saving;
    if (_autosaveFailed) return _EditorAutosaveState.failed;
    if (_changed) return _EditorAutosaveState.pending;
    if (_entry == null) return _EditorAutosaveState.enabled;
    return _EditorAutosaveState.saved;
  }

  String _autosaveStatusLabel(BuildContext context) => switch (_autosaveState) {
    _EditorAutosaveState.enabled => context.l10n.autosaveEnabled,
    _EditorAutosaveState.pending => context.l10n.autosavePending,
    _EditorAutosaveState.saving => context.l10n.autosaving,
    _EditorAutosaveState.saved => context.l10n.autosavedLocally,
    _EditorAutosaveState.failed => context.l10n.autosaveFailedShort,
  };

  Future<void> _clearRecoveryDrafts() async {
    final persistedId = _entry?.id;
    if (widget.existingEntry?.id == null && persistedId != null) {
      await _draftRecovery.clearAfterCreation(persistedId);
    } else {
      await _draftRecovery.clear(persistedId ?? widget.existingEntry?.id);
    }
  }

  List<NoteAttachment> get _orderedAttachments => [
    for (var index = 0; index < _attachments.length; index++)
      _attachments[index].copyWith(sortOrder: index),
  ];

  Future<void> _showAddContentSheet() async {
    if (_importing) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.addToNote,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _AddContentAction(
                    icon: Icons.photo_library_outlined,
                    label: context.l10n.image,
                    onTap: () => _runAfterSheet(sheetContext, _pickImages),
                  ),
                  _AddContentAction(
                    icon: Icons.camera_alt_outlined,
                    label: context.l10n.camera,
                    onTap: () => _runAfterSheet(sheetContext, _takePhoto),
                  ),
                  _AddContentAction(
                    icon: Icons.mic_none_rounded,
                    label: context.l10n.record,
                    onTap: () => _runAfterSheet(sheetContext, _recordAudio),
                  ),
                  _AddContentAction(
                    icon: Icons.audio_file_outlined,
                    label: context.l10n.audio,
                    onTap: () => _runAfterSheet(sheetContext, _pickAudio),
                  ),
                  _AddContentAction(
                    icon: Icons.video_file_outlined,
                    label: context.l10n.video,
                    onTap: () => _runAfterSheet(sheetContext, _pickVideo),
                  ),
                  _AddContentAction(
                    icon: Icons.attach_file_rounded,
                    label: context.l10n.file,
                    onTap: () => _runAfterSheet(sheetContext, _pickDocument),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _runAfterSheet(BuildContext sheetContext, Future<void> Function() task) {
    Navigator.pop(sheetContext);
    Future<void>.delayed(const Duration(milliseconds: 220), task);
  }

  Future<void> _pickImages() => _pickAttachment(NoteType.image);

  Future<void> _takePhoto() => _pickAttachment(NoteType.image, camera: true);

  Future<void> _pickVideo() => _pickAttachment(NoteType.video);

  Future<void> _pickAudio() => _pickAttachment(NoteType.audio);

  Future<void> _pickDocument() => _pickAttachment(NoteType.document);

  Future<void> _pickAttachment(NoteType type, {bool camera = false}) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final provider = context.read<NoteProvider>();
      final jobs = await provider.startAttachmentImport(
        type,
        noteId: _entry?.id,
        camera: camera,
      );
      if (jobs.isEmpty || !mounted) return;
      final draft = jobs.first.noteId == null
          ? null
          : provider.getEntryById(jobs.first.noteId!);
      setState(() {
        _importJobIds.addAll(jobs.map((job) => job.id));
        if (_entry == null && draft != null) {
          _entry = draft;
          if (_title.text.trim().isEmpty) {
            _lastTitleText = draft.title;
            _title.text = draft.title;
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is PlatformException
          ? error.message ??
                context.l10n.attachmentImportTypeFailed(
                  _noteTypeLabel(context, type),
                )
          : error.toString();
      AppFeedback.error(context, message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeAttachmentImport(AttachmentImportJob job) async {
    final provider = context.read<NoteProvider>();
    await provider.removeAttachmentImport(job.id);
    if (mounted) setState(() => _importJobIds.remove(job.id));
  }

  Future<void> _retryAttachmentImport(AttachmentImportJob job) async {
    await _removeAttachmentImport(job);
    if (mounted) await _pickAttachment(job.type);
  }

  Future<void> _recordAudio() async {
    final attachment = await Navigator.push<NoteAttachment>(
      context,
      MaterialPageRoute(
        builder: (_) => const RecordAudioPage(returnAttachment: true),
      ),
    );
    if (attachment != null) _addAttachments([attachment]);
  }

  void _addAttachments(List<NoteAttachment> items) {
    if (!mounted || items.isEmpty) return;
    setState(() {
      _attachments.addAll(items);
      _changed = true;
    });
    _scheduleAutosave();
    _queueRecoveryDraft();
  }

  void _moveAttachment(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _attachments.length) return;
    setState(() {
      final item = _attachments.removeAt(index);
      _attachments.insert(target, item);
      _changed = true;
    });
    _scheduleAutosave();
    _queueRecoveryDraft();
  }

  void _removeAttachment(int index) {
    setState(() {
      _removedAttachments.add(_attachments.removeAt(index));
      _changed = true;
    });
    _scheduleAutosave();
    _queueRecoveryDraft();
  }

  Future<void> _renameAttachment(int index) async {
    final attachment = _attachments[index];
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AttachmentTitleSheet(attachment: attachment),
    );
    if (title == null || !mounted || index >= _attachments.length) return;
    final normalized = title.trim();
    setState(() {
      _attachments[index] =
          normalized.isEmpty || normalized == attachment.fileName
          ? attachment.copyWith(clearDisplayName: true)
          : attachment.copyWith(displayName: normalized);
      _changed = true;
    });
    _scheduleAutosave();
    _queueRecoveryDraft();
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    _autosave?.cancel();
    if (_changed && !await _persist()) return;
    final entry = _entry;
    if (entry == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaDetailPage(entry: entry, attachment: attachment),
      ),
    );
    if (!mounted || entry.id == null) return;
    final refreshed = context.read<NoteProvider>().getEntryById(entry.id!);
    if (refreshed != null) {
      setState(() {
        _entry = refreshed;
        _attachments = [...refreshed.allAttachments];
      });
    }
  }

  Future<void> _close() async {
    _autosave?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final saved = !_changed || await _persist();
    if (saved && mounted) Navigator.pop(context);
  }

  Future<void> _editTags() async {
    final tags = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TagEditorSheet(initialTags: _tags),
    );
    if (tags != null && mounted) {
      setState(() {
        _tags = tags;
        _changed = true;
      });
      _scheduleAutosave();
      _queueRecoveryDraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final diagnosticsWidth = _dictationDiagnosticsWidth.clamp(
      280.0,
      screenSize.width - 24,
    );
    final diagnosticsHeight = _dictationDiagnosticsHeight.clamp(
      220.0,
      screenSize.height - _dictationDiagnosticsTop - 12,
    );
    final provider = context.read<NoteProvider>();
    final importJobs = _importJobIds
        .map(provider.attachmentImportJob)
        .whereType<AttachmentImportJob>()
        .toList(growable: false);
    final hasAttachmentContent =
        _attachments.isNotEmpty || importJobs.isNotEmpty;
    final autosaveState = _autosaveState;
    final autosaveLabel = _autosaveStatusLabel(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          leading: IconButton(
            key: const Key('note-editor-back'),
            tooltip: context.l10n.back,
            onPressed: _close,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _isEditing ? context.l10n.editNote : context.l10n.newNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _AutosaveStatusIcon(
                    state: autosaveState,
                    label: autosaveLabel,
                  ),
                ],
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _content,
                builder: (context, value, child) => Text(
                  '$autosaveLabel · '
                  '${context.l10n.characterCount(NoteBlockCodec.visibleCharacterCount(value.text))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('note-read-aloud'),
              tooltip: _readAloud.isActive
                  ? context.l10n.stopReadAloud
                  : context.l10n.readNoteAloud,
              onPressed: _toggleReadAloud,
              icon: _readAloud.status == ReadAloudStatus.generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _readAloud.isActive
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                    ),
            ),
            AppAnchoredMenuButton<String>(
              tooltip: context.l10n.moreNoteActions,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (value == 'favorite') _favorite = !_favorite;
                  if (value == 'pin') _pinned = !_pinned;
                  _changed = true;
                });
                _scheduleAutosave();
                _queueRecoveryDraft();
              },
              actions: [
                AppMenuAction(
                  value: 'favorite',
                  icon: _favorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: _favorite
                      ? context.l10n.removeFavorite
                      : context.l10n.addFavorite,
                  selected: _favorite,
                ),
                AppMenuAction(
                  value: 'pin',
                  icon: Icons.vertical_align_top_rounded,
                  label: _pinned ? context.l10n.unpin : context.l10n.pin,
                  selected: _pinned,
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: const Key('note-editor-scroll-surface'),
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _blockEditorKey.currentState?.focusAtEnd(),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _title,
                                contextMenuBuilder:
                                    buildAppEditableTextContextMenu,
                                maxLines: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  fontFamily: 'serif',
                                  fontSize: 28,
                                  height: 1.22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: context.l10n.title,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final tag in _tags)
                                    InputChip(
                                      label: Text('#$tag'),
                                      onDeleted: () {
                                        setState(() {
                                          _tags.remove(tag);
                                          _changed = true;
                                        });
                                        _scheduleAutosave();
                                        _queueRecoveryDraft();
                                      },
                                    ),
                                  ActionChip(
                                    avatar: const Icon(
                                      Icons.add_rounded,
                                      size: 17,
                                    ),
                                    label: Text(
                                      _tags.isEmpty
                                          ? context.l10n.addTags
                                          : context.l10n.tags,
                                    ),
                                    onPressed: _editTags,
                                  ),
                                ],
                              ),
                              if (hasAttachmentContent) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        context.l10n.noteContent,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.muted,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      context.l10n.attachmentItemCount(
                                        _attachments.length + importJobs.length,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (
                                  var index = 0;
                                  index < importJobs.length;
                                  index++
                                ) ...[
                                  _AttachmentImportTile(
                                    job: importJobs[index],
                                    onCancel: () => _removeAttachmentImport(
                                      importJobs[index],
                                    ),
                                    onRetry: () => _retryAttachmentImport(
                                      importJobs[index],
                                    ),
                                    onRemove: () => _removeAttachmentImport(
                                      importJobs[index],
                                    ),
                                  ),
                                  if (index < importJobs.length - 1 ||
                                      _attachments.isNotEmpty)
                                    const SizedBox(height: 8),
                                ],
                                for (
                                  var index = 0;
                                  index < _attachments.length;
                                  index++
                                ) ...[
                                  _AttachmentEditorTile(
                                    attachment: _attachments[index],
                                    onRename: () => _renameAttachment(index),
                                    onOpen: () =>
                                        _openAttachment(_attachments[index]),
                                    onReference: () => _blockEditorKey
                                        .currentState
                                        ?.insertAttachmentReference(
                                          _attachments[index].filePath,
                                        ),
                                    canMoveUp: index > 0,
                                    canMoveDown:
                                        index < _attachments.length - 1,
                                    onMoveUp: () => _moveAttachment(index, -1),
                                    onMoveDown: () => _moveAttachment(index, 1),
                                    onRemove: () => _removeAttachment(index),
                                  ),
                                  if (index < _attachments.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Divider(),
                              ),
                              NoteBlockEditor(
                                key: _blockEditorKey,
                                controller: _content,
                                initialRichContent: _richContent,
                                onRichContentChanged: _onRichContentChanged,
                                attachments: _attachments,
                                onOpenAttachment: _openAttachment,
                                minLines: hasAttachmentContent ? 10 : 16,
                                hintText: hasAttachmentContent
                                    ? context.l10n.noteDescriptionHint
                                    : context.l10n.noteStartHint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.line)),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                      child: TextFieldTapRegion(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_dictation.isActive ||
                                _dictation.status ==
                                    RealtimeDictationStatus.failed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LiveDictationBar(
                                  service: _dictation,
                                  onCancel: _cancelDictation,
                                  onShowDiagnostics: kDebugMode
                                      ? () => setState(
                                          () =>
                                              _showDictationDiagnostics = true,
                                        )
                                      : null,
                                  onFinish:
                                      _dictation.status ==
                                          RealtimeDictationStatus.listening
                                      ? _stopDictation
                                      : null,
                                ),
                              ),
                            Row(
                              children: [
                                IconButton.filled(
                                  tooltip: context.l10n.addMediaOrFile,
                                  onPressed: _importing || _dictation.isActive
                                      ? null
                                      : _showAddContentSheet,
                                  icon: _importing
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.add_rounded),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _ScrollableEditorToolbar(
                                    child: _EditorToolbar(
                                      editorKey: _blockEditorKey,
                                      onAssistant: _openLocalAssistant,
                                      onDictation: _toggleDictation,
                                      dictationStatus: _dictation.status,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (kDebugMode && _showDictationDiagnostics)
              Positioned(
                top: _dictationDiagnosticsTop,
                left: _dictationDiagnosticsLeft,
                width: diagnosticsWidth,
                child: _DictationDiagnosticsOverlay(
                  service: _dictation,
                  collapsed: _dictationDiagnosticsCollapsed,
                  height: diagnosticsHeight,
                  onMove: (delta) {
                    setState(() {
                      final panelHeight = _dictationDiagnosticsCollapsed
                          ? 72.0
                          : diagnosticsHeight;
                      final maxLeft = screenSize.width - diagnosticsWidth - 12;
                      final maxTop = screenSize.height - panelHeight - 12;
                      _dictationDiagnosticsLeft =
                          (_dictationDiagnosticsLeft + delta.dx).clamp(
                            12.0,
                            maxLeft < 12 ? 12.0 : maxLeft,
                          );
                      _dictationDiagnosticsTop =
                          (_dictationDiagnosticsTop + delta.dy).clamp(
                            12.0,
                            maxTop < 12 ? 12.0 : maxTop,
                          );
                    });
                  },
                  onResize: (delta) {
                    setState(() {
                      final maxWidth =
                          screenSize.width - _dictationDiagnosticsLeft - 12;
                      final maxHeight =
                          screenSize.height - _dictationDiagnosticsTop - 12;
                      _dictationDiagnosticsWidth =
                          (_dictationDiagnosticsWidth + delta.dx).clamp(
                            280.0,
                            maxWidth < 280 ? 280.0 : maxWidth,
                          );
                      _dictationDiagnosticsHeight =
                          (_dictationDiagnosticsHeight + delta.dy).clamp(
                            220.0,
                            maxHeight < 220 ? 220.0 : maxHeight,
                          );
                    });
                  },
                  onToggleCollapsed: () => setState(() {
                    _dictationDiagnosticsCollapsed =
                        !_dictationDiagnosticsCollapsed;
                  }),
                  onClose: () =>
                      setState(() => _showDictationDiagnostics = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutosaveStatusIcon extends StatelessWidget {
  final _EditorAutosaveState state;
  final String label;

  const _AutosaveStatusIcon({required this.state, required this.label});

  @override
  Widget build(BuildContext context) {
    final foreground = switch (state) {
      _EditorAutosaveState.enabled => AppColors.muted,
      _EditorAutosaveState.pending => AppColors.muted,
      _EditorAutosaveState.saving => AppColors.moss,
      _EditorAutosaveState.saved => AppColors.moss,
      _EditorAutosaveState.failed => AppColors.coral,
    };
    final icon = switch (state) {
      _EditorAutosaveState.enabled => Icons.save_outlined,
      _EditorAutosaveState.pending => Icons.schedule_rounded,
      _EditorAutosaveState.saving => null,
      _EditorAutosaveState.saved => Icons.check_rounded,
      _EditorAutosaveState.failed => Icons.error_outline_rounded,
    };

    return Semantics(
      container: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox(
          key: const Key('note-autosave-status'),
          width: 18,
          height: 18,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: icon == null
                  ? SizedBox(
                      key: ValueKey(state),
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: foreground,
                      ),
                    )
                  : Icon(
                      icon,
                      key: ValueKey(state),
                      size: state == _EditorAutosaveState.saved ? 17 : 16,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableEditorToolbar extends StatefulWidget {
  final Widget child;

  const _ScrollableEditorToolbar({required this.child});

  @override
  State<_ScrollableEditorToolbar> createState() =>
      _ScrollableEditorToolbarState();
}

class _ScrollableEditorToolbarState extends State<_ScrollableEditorToolbar> {
  final _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshEdges);
  }

  void _refreshEdges() {
    if (!_controller.hasClients) return;
    final left = _controller.offset > 1;
    final right = _controller.offset < _controller.position.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshEdges)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshEdges();
    });
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
        if (_canScrollLeft)
          const Positioned.fill(
            right: null,
            child: _ToolbarEdgeFade(left: true),
          ),
        if (_canScrollRight)
          const Positioned.fill(
            left: null,
            child: _ToolbarEdgeFade(left: false),
          ),
      ],
    );
  }
}

class _ToolbarEdgeFade extends StatelessWidget {
  final bool left;

  const _ToolbarEdgeFade({required this.left});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [AppColors.surface, Color(0x00FFFDFC)],
        ),
      ),
    ),
  );
}

class _TagEditorSheet extends StatefulWidget {
  final List<String> initialTags;

  const _TagEditorSheet({required this.initialTags});

  @override
  State<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<_TagEditorSheet> {
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

  static List<String> _parseTags(String value) => value
      .split(RegExp('[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .take(8)
      .toList();

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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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

class _EditorToolbar extends StatefulWidget {
  final GlobalKey<NoteBlockEditorState> editorKey;
  final VoidCallback onAssistant;
  final VoidCallback onDictation;
  final RealtimeDictationStatus dictationStatus;

  const _EditorToolbar({
    required this.editorKey,
    required this.onAssistant,
    required this.onDictation,
    required this.dictationStatus,
  });

  @override
  State<_EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<_EditorToolbar> {
  ValueNotifier<NoteBlockType>? _activeType;
  ValueNotifier<NoteEditorFormatState>? _activeFormat;
  ValueNotifier<NoteHistoryState>? _historyState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editor = widget.editorKey.currentState;
      final typeNotifier = editor?.activeType;
      final formatNotifier = editor?.activeFormat;
      final historyNotifier = editor?.historyState;
      if (identical(typeNotifier, _activeType) &&
          identical(formatNotifier, _activeFormat) &&
          identical(historyNotifier, _historyState)) {
        return;
      }
      _activeType?.removeListener(_refresh);
      _activeFormat?.removeListener(_refresh);
      _historyState?.removeListener(_refresh);
      _activeType = typeNotifier?..addListener(_refresh);
      _activeFormat = formatNotifier?..addListener(_refresh);
      _historyState = historyNotifier?..addListener(_refresh);
      _refresh();
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _editLink() async {
    final editor = widget.editorKey.currentState;
    if (editor == null) return;
    final result = await showModalBottomSheet<_LinkEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LinkEditorSheet(initialValue: _activeFormat?.value.link),
    );
    if (result == null || !mounted) return;
    editor.setLink(result.remove ? null : result.value);
  }

  @override
  void dispose() {
    _activeType?.removeListener(_refresh);
    _activeFormat?.removeListener(_refresh);
    _historyState?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeType?.value ?? NoteBlockType.paragraph;
    final format = _activeFormat?.value ?? const NoteEditorFormatState();
    final history = _historyState?.value ?? const NoteHistoryState();
    final editor = widget.editorKey.currentState;
    final dictating =
        widget.dictationStatus == RealtimeDictationStatus.listening;
    final dictationBusy =
        widget.dictationStatus == RealtimeDictationStatus.preparing ||
        widget.dictationStatus == RealtimeDictationStatus.stopping;
    return Row(
      children: [
        _EditorAiButton(
          key: const Key('note-editor-assistant'),
          onPressed: widget.onAssistant,
        ),
        _EditorToolButton(
          tooltip: dictating
              ? context.l10n.stopLiveDictation
              : context.l10n.liveVoiceInput,
          icon: dictating ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
          selected: dictating,
          onPressed: dictationBusy ? null : widget.onDictation,
        ),
        _EditorToolButton(
          tooltip: context.l10n.undo,
          icon: Icons.undo_rounded,
          selected: false,
          onPressed: history.canUndo ? editor?.undo : null,
        ),
        _EditorToolButton(
          tooltip: context.l10n.redo,
          icon: Icons.redo_rounded,
          selected: false,
          onPressed: history.canRedo ? editor?.redo : null,
        ),
        _EditorToolButton(
          tooltip: context.l10n.bold,
          icon: Icons.format_bold_rounded,
          selected: format.bold,
          onPressed: editor?.toggleBold,
        ),
        _EditorToolButton(
          tooltip: context.l10n.italic,
          icon: Icons.format_italic_rounded,
          selected: format.italic,
          onPressed: editor?.toggleItalic,
        ),
        _EditorToolButton(
          tooltip: context.l10n.underline,
          icon: Icons.format_underlined_rounded,
          selected: format.underline,
          onPressed: editor?.toggleUnderline,
        ),
        _BlockStyleMenuButton(
          active: active,
          headingLevel: format.headingLevel,
          enabled: editor != null,
          onSelected: (value) {
            if (editor == null) return;
            if (value == 'paragraph') {
              editor.setHeadingLevel(null);
            } else if (value == 'code') {
              editor.toggleBlock(NoteBlockType.code);
            } else if (value == 'quote') {
              editor.toggleBlock(NoteBlockType.quote);
            } else if (value == 'divider') {
              editor.insertDivider();
            } else if (value.startsWith('h')) {
              editor.setHeadingLevel(int.parse(value.substring(1)));
            }
          },
        ),
        _ListStyleMenuButton(
          active: active,
          indent: format.indent,
          enabled: editor != null,
          onSelected: (value) {
            if (editor == null) return;
            switch (value) {
              case 'todo':
                editor.toggleBlock(NoteBlockType.todo);
              case 'bullet':
                editor.toggleBlock(NoteBlockType.bullet);
              case 'ordered':
                editor.toggleBlock(NoteBlockType.ordered);
              case 'outdent':
                editor.changeIndent(-1);
              case 'indent':
                editor.changeIndent(1);
            }
          },
        ),
        _MoreFormattingMenuButton(
          format: format,
          enabled: editor != null,
          onSelected: (value) {
            if (editor == null) return;
            switch (value) {
              case 'strikethrough':
                editor.toggleStrikethrough();
              case 'inline-code':
                editor.toggleInlineCode();
              case 'link':
                unawaited(_editLink());
            }
          },
        ),
      ],
    );
  }
}

class _LinkEditResult {
  final String? value;
  final bool remove;

  const _LinkEditResult.save(this.value) : remove = false;
  const _LinkEditResult.remove() : value = null, remove = true;
}

class _LinkEditorSheet extends StatefulWidget {
  final String? initialValue;

  const _LinkEditorSheet({this.initialValue});

  @override
  State<_LinkEditorSheet> createState() => _LinkEditorSheetState();
}

class _LinkEditorSheetState extends State<_LinkEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, _LinkEditResult.save(value));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initialValue == null
                  ? context.l10n.addLink
                  : context.l10n.editLink,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.linkPrivacyDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('note-link-field'),
              controller: _controller,
              contextMenuBuilder: buildAppEditableTextContextMenu,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: context.l10n.linkAddress,
                hintText: 'https://example.com',
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 20),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                if (widget.initialValue != null)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, const _LinkEditResult.remove()),
                    icon: const Icon(Icons.link_off_rounded),
                    label: Text(context.l10n.removeLink),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: _save,
                  child: Text(context.l10n.completed),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDictationBar extends StatelessWidget {
  final RealtimeDictationService service;
  final VoidCallback onCancel;
  final VoidCallback? onFinish;
  final VoidCallback? onShowDiagnostics;

  const _LiveDictationBar({
    required this.service,
    required this.onCancel,
    required this.onFinish,
    required this.onShowDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = service.elapsed.inSeconds;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final label = switch (service.status) {
      RealtimeDictationStatus.preparing => context.l10n.loadingLocalModel,
      RealtimeDictationStatus.stopping => context.l10n.organizingLastSentence,
      RealtimeDictationStatus.failed =>
        service.errorMessage ?? context.l10n.liveDictationFailed,
      _ =>
        service.partialText.isEmpty
            ? context.l10n.listening
            : service.partialText,
    };
    final useCompactFinish =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _InputLevel(level: service.inputLevel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.status == RealtimeDictationStatus.listening
                            ? context.l10n.liveDictationElapsed(time)
                            : context.l10n.localVoiceInput,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.coral,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    RealtimeDictationProviderBadge(
                      provider: service.activeExecutionProvider,
                      fallback: service.usedExecutionProviderFallback,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (onShowDiagnostics != null)
            IconButton(
              tooltip: '实时听写诊断',
              onPressed: onShowDiagnostics,
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          IconButton(
            tooltip: context.l10n.cancelDictation,
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
          if (onFinish != null)
            if (useCompactFinish)
              IconButton.filled(
                tooltip: context.l10n.finishDictation,
                onPressed: onFinish,
                icon: const Icon(Icons.check_rounded, size: 20),
              )
            else
              FilledButton(
                onPressed: onFinish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 38),
                ),
                child: Text(context.l10n.completed),
              ),
        ],
      ),
    );
  }
}

class _DictationDiagnosticsOverlay extends StatefulWidget {
  final RealtimeDictationService service;
  final bool collapsed;
  final double height;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onClose;

  const _DictationDiagnosticsOverlay({
    required this.service,
    required this.collapsed,
    required this.height,
    required this.onMove,
    required this.onResize,
    required this.onToggleCollapsed,
    required this.onClose,
  });

  @override
  State<_DictationDiagnosticsOverlay> createState() =>
      _DictationDiagnosticsOverlayState();
}

class _DictationDiagnosticsOverlayState
    extends State<_DictationDiagnosticsOverlay> {
  final _scrollController = ScrollController();

  RealtimeDictationService get service => widget.service;
  bool get collapsed => widget.collapsed;
  double get height => widget.height;
  ValueChanged<Offset> get onMove => widget.onMove;
  ValueChanged<Offset> get onResize => widget.onResize;
  VoidCallback get onToggleCollapsed => widget.onToggleCollapsed;
  VoidCallback get onClose => widget.onClose;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followLatestIfNeeded() {
    final shouldFollow =
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter < 32;
    if (!shouldFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('dictation-debug-overlay'),
    color: const Color(0xEE181818),
    elevation: 12,
    shadowColor: Colors.black54,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!collapsed) _followLatestIfNeeded();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onMove(details.delta),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
                child: Row(
                  children: [
                    const Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '实时听写诊断 · Debug only',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: collapsed ? '展开' : '折叠',
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleCollapsed,
                      icon: Icon(
                        collapsed
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        size: 19,
                        color: Colors.white70,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭诊断窗口',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              const Divider(height: 1, color: Colors.white12),
              SizedBox(
                height: (height - 116).clamp(100.0, 520.0),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                    child: SelectableText(
                      service.debugReport,
                      contextMenuBuilder: buildAppEditableTextContextMenu,
                      style: const TextStyle(
                        color: Color(0xFFD8F8D2),
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: service.clearDebugDiagnostics,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('export-dictation-debug-audio'),
                      onPressed: service.debugAudioAvailable
                          ? () async {
                              final file = await service
                                  .createDebugAudioExport();
                              if (file == null) return;
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [
                                    XFile(
                                      file.path,
                                      mimeType: 'audio/wav',
                                      name: file.uri.pathSegments.last,
                                    ),
                                  ],
                                  title: 'FKNotes 实时听写诊断录音',
                                  subject: '模型实际收到的 PCM16 音频',
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.audio_file_outlined, size: 17),
                      label: const Text('导出录音'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      key: const Key('copy-dictation-debug-report'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: service.debugReport),
                        );
                        if (!context.mounted) return;
                        AppFeedback.success(context, '诊断信息已复制');
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 17),
                      label: const Text('复制全部'),
                    ),
                    const SizedBox(width: 4),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        key: const Key('resize-dictation-debug-overlay'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) => onResize(details.delta),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 17,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _InputLevel extends StatelessWidget {
  final double level;
  const _InputLevel({required this.level});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 28,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var index = 0; index < 4; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 6 + 20 * (level * (1 + index * .18)).clamp(0.0, 1.0),
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    ),
  );
}

class _EditorToolButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  const _EditorToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: selected ? AppColors.softGreen : Colors.transparent,
      foregroundColor: selected ? AppColors.coral : AppColors.muted,
    ),
    icon: Icon(icon),
  );
}

class _EditorAiButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EditorAiButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.localAssistant,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.muted,
    ),
    icon: const Text(
      'AI',
      style: TextStyle(
        color: AppColors.muted,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
      ),
    ),
  );
}

class _BlockStyleMenuButton extends StatelessWidget {
  final NoteBlockType active;
  final int headingLevel;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const _BlockStyleMenuButton({
    required this.active,
    required this.headingLevel,
    required this.enabled,
    required this.onSelected,
  });

  String _label(BuildContext context) {
    if (active == NoteBlockType.heading) return 'H$headingLevel';
    if (active == NoteBlockType.code) return '</>';
    return '¶';
  }

  @override
  Widget build(BuildContext context) => AppAnchoredMenuButton<String>(
    tooltip: context.l10n.paragraphStyle,
    enabled: enabled,
    onSelected: onSelected,
    actions: [
      _action('paragraph', context.l10n.paragraph, Icons.notes_rounded),
      for (var level = 1; level <= 6; level++)
        _action(
          'h$level',
          context.l10n.headingLevel(level),
          Icons.title_rounded,
        ),
      _action('quote', context.l10n.quote, Icons.format_quote_rounded),
      _action('code', context.l10n.codeBlock, Icons.data_object_rounded),
      _action('divider', context.l10n.divider, Icons.horizontal_rule_rounded),
    ],
    child: SizedBox(
      width: 58,
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _label(context),
            style: TextStyle(
              color:
                  active == NoteBlockType.heading ||
                      active == NoteBlockType.code
                  ? AppColors.coral
                  : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            size: 16,
            color: AppColors.muted,
          ),
        ],
      ),
    ),
  );

  AppMenuAction<String> _action(String value, String label, IconData icon) {
    final selected = value == 'paragraph'
        ? active == NoteBlockType.paragraph
        : value == 'code'
        ? active == NoteBlockType.code
        : value == 'quote'
        ? active == NoteBlockType.quote
        : value == 'divider'
        ? active == NoteBlockType.divider
        : active == NoteBlockType.heading && value == 'h$headingLevel';
    return AppMenuAction(
      value: value,
      icon: icon,
      label: label,
      selected: selected,
    );
  }
}

class _ListStyleMenuButton extends StatelessWidget {
  final NoteBlockType active;
  final int indent;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const _ListStyleMenuButton({
    required this.active,
    required this.indent,
    required this.enabled,
    required this.onSelected,
  });

  bool _isSelected(NoteBlockType type) => active == type;

  @override
  Widget build(BuildContext context) => AppAnchoredMenuButton<String>(
    tooltip: context.l10n.listsAndIndentation,
    enabled: enabled,
    onSelected: onSelected,
    actions: [
      AppMenuAction(
        value: 'todo',
        label: context.l10n.todoItem,
        icon: Icons.check_box_outlined,
        selected: _isSelected(NoteBlockType.todo),
      ),
      AppMenuAction(
        value: 'bullet',
        label: context.l10n.bulletList,
        icon: Icons.format_list_bulleted_rounded,
        selected: _isSelected(NoteBlockType.bullet),
      ),
      AppMenuAction(
        value: 'ordered',
        label: context.l10n.numberedList,
        icon: Icons.format_list_numbered_rounded,
        selected: _isSelected(NoteBlockType.ordered),
      ),
      AppMenuAction(
        value: 'outdent',
        label: context.l10n.decreaseIndent,
        icon: Icons.format_indent_decrease_rounded,
        enabled: indent > 0,
      ),
      AppMenuAction(
        value: 'indent',
        label: context.l10n.increaseIndent,
        icon: Icons.format_indent_increase_rounded,
        enabled: indent < 3,
      ),
    ],
    child: _ToolbarMenuIcon(
      icon: switch (active) {
        NoteBlockType.todo => Icons.check_box_outlined,
        NoteBlockType.ordered => Icons.format_list_numbered_rounded,
        _ => Icons.format_list_bulleted_rounded,
      },
      selected:
          active == NoteBlockType.todo ||
          active == NoteBlockType.bullet ||
          active == NoteBlockType.ordered ||
          indent > 0,
    ),
  );
}

class _MoreFormattingMenuButton extends StatelessWidget {
  final NoteEditorFormatState format;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const _MoreFormattingMenuButton({
    required this.format,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => AppAnchoredMenuButton<String>(
    tooltip: context.l10n.moreFormatting,
    enabled: enabled,
    onSelected: onSelected,
    actions: [
      AppMenuAction(
        value: 'strikethrough',
        label: context.l10n.strikethrough,
        icon: Icons.strikethrough_s_rounded,
        selected: format.strikethrough,
      ),
      AppMenuAction(
        value: 'inline-code',
        label: context.l10n.inlineCode,
        icon: Icons.code_rounded,
        selected: format.inlineCode,
      ),
      AppMenuAction(
        value: 'link',
        label: format.link == null
            ? context.l10n.addLink
            : context.l10n.editLink,
        icon: Icons.link_rounded,
        selected: format.link != null,
      ),
    ],
    child: _ToolbarMenuIcon(
      icon: Icons.text_format_rounded,
      selected:
          format.strikethrough || format.inlineCode || format.link != null,
    ),
  );
}

class _ToolbarMenuIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _ToolbarMenuIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 21,
          color: selected ? AppColors.coral : AppColors.muted,
        ),
        const Icon(
          Icons.arrow_drop_down_rounded,
          size: 14,
          color: AppColors.muted,
        ),
      ],
    ),
  );
}

class _AddContentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddContentAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.softAmber,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.moss),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _AttachmentImportTile extends StatelessWidget {
  final AttachmentImportJob job;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _AttachmentImportTile({
    required this.job,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final progress = job.progress;
    final color = NoteCard.colorForType(job.type);
    final statusText = switch (job.status) {
      AttachmentImportStatus.importing =>
        job.type == NoteType.image && progress == 1
            ? context.l10n.generatingThumbnail
            : progress == null
            ? context.l10n.importingBytes(_formatBytes(job.copiedBytes))
            : context.l10n.importingPercent(
                (progress * 100).round(),
                '${_formatBytes(job.copiedBytes)} / ${_formatBytes(job.totalBytes)}',
              ),
      AttachmentImportStatus.completed => context.l10n.importCompleteSaving,
      AttachmentImportStatus.failed =>
        job.errorMessage?.trim().isNotEmpty == true
            ? context.l10n.importFailedDetail(job.errorMessage!)
            : context.l10n.importFailedRetry,
      AttachmentImportStatus.canceled => context.l10n.importCanceled,
    };
    return Material(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(NoteCard.iconForType(job.type), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: job.status == AttachmentImportStatus.failed
                          ? color
                          : AppColors.muted,
                    ),
                  ),
                  if (job.status == AttachmentImportStatus.importing ||
                      job.status == AttachmentImportStatus.completed) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: job.status == AttachmentImportStatus.completed
                            ? 1
                            : progress,
                        minHeight: 4,
                        backgroundColor: AppColors.line,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (job.status == AttachmentImportStatus.importing)
              IconButton(
                tooltip: context.l10n.cancelImport,
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              )
            else if (job.status == AttachmentImportStatus.failed) ...[
              IconButton(
                tooltip: context.l10n.chooseTypeAgain(
                  _noteTypeLabel(context, job.type),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: context.l10n.remove,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class _AttachmentEditorTile extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback onRename;
  final VoidCallback onOpen;
  final VoidCallback onReference;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  const _AttachmentEditorTile({
    required this.attachment,
    required this.onRename,
    required this.onOpen,
    required this.onReference,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = NoteCard.colorForType(attachment.type);
    final thumbnailPath = attachment.thumbnailPath;
    final thumbnail = thumbnailPath == null
        ? null
        : File(FileStorageService.instance.absolutePath(thumbnailPath));
    return Material(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumbnail?.existsSync() == true
                    ? Image.file(
                        thumbnail!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 54,
                        height: 54,
                        color: color.withValues(alpha: .1),
                        child: Icon(
                          NoteCard.iconForType(attachment.type),
                          color: color,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_noteTypeLabel(context, attachment.type)} · ${_formatSize(attachment.fileSize)}${attachment.ocrText?.trim().isNotEmpty == true ? ' · OCR' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              AppAnchoredMenuButton<String>(
                key: ValueKey('attachment-menu-${attachment.filePath}'),
                tooltip: context.l10n.adjustAttachment,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                    case 'up':
                      onMoveUp();
                    case 'down':
                      onMoveDown();
                    case 'reference':
                      onReference();
                    case 'remove':
                      onRemove();
                  }
                },
                actions: [
                  AppMenuAction(
                    value: 'rename',
                    icon: Icons.edit_outlined,
                    label: context.l10n.renameAttachment,
                  ),
                  AppMenuAction(
                    value: 'up',
                    enabled: canMoveUp,
                    icon: Icons.arrow_upward_rounded,
                    label: context.l10n.moveUp,
                  ),
                  AppMenuAction(
                    value: 'down',
                    enabled: canMoveDown,
                    icon: Icons.arrow_downward_rounded,
                    label: context.l10n.moveDown,
                  ),
                  AppMenuAction(
                    value: 'reference',
                    icon: Icons.add_link_rounded,
                    label: context.l10n.referenceInBody,
                  ),
                  AppMenuAction(
                    value: 'remove',
                    icon: Icons.remove_circle_outline_rounded,
                    label: context.l10n.remove,
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class _AttachmentTitleSheet extends StatefulWidget {
  final NoteAttachment attachment;

  const _AttachmentTitleSheet({required this.attachment});

  @override
  State<_AttachmentTitleSheet> createState() => _AttachmentTitleSheetState();
}

class _AttachmentTitleSheetState extends State<_AttachmentTitleSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.attachment.displayTitle);
    _controller.addListener(_handleChanged);
  }

  void _handleChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.editAttachmentTitle,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.attachmentTitleDescription,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('attachment-title-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.l10n.attachmentTitle,
              hintText: context.l10n.attachmentTitleHint,
            ),
            onSubmitted: canSave
                ? (_) => Navigator.pop(context, _controller.text.trim())
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.attachment.displayName?.trim().isNotEmpty == true)
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(context.l10n.restoreOriginalFileName),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('save-attachment-title'),
                onPressed: canSave
                    ? () => Navigator.pop(context, _controller.text.trim())
                    : null,
                child: Text(context.l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _noteTypeLabel(BuildContext context, NoteType type) => switch (type) {
  NoteType.text => context.l10n.note,
  NoteType.image => context.l10n.image,
  NoteType.audio => context.l10n.audio,
  NoteType.video => context.l10n.video,
  NoteType.document => context.l10n.file,
};

String _assistantResultHeading(
  BuildContext context,
  NoteAssistantAction action,
) => switch (action.task) {
  NoteAssistantTask.summarize => context.l10n.assistantSummaryHeading,
  NoteAssistantTask.extractTodos => context.l10n.assistantTodosHeading,
  NoteAssistantTask.polish => context.l10n.assistantPolishedHeading,
  null => context.l10n.assistantGeneratedHeading,
};
