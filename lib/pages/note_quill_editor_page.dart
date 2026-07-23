import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app.dart';
import '../editor/note_assistant_editing.dart';
import '../editor/note_editor_controller.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../models/local_llm.dart';
import '../models/note.dart';
import '../models/note_document.dart';
import '../models/note_share.dart';
import '../models/note_semantic_projection.dart';
import '../services/file_storage_service.dart';
import '../services/kokoro_tts_model_service.dart';
import '../services/language_model_service.dart';
import '../services/local_model_manager.dart';
import '../services/local_assistant_service.dart';
import '../services/local_llm/local_llm_output_filter.dart';
import '../services/note_asset_import_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/note_database_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_repository.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_assistant_sheet.dart';
import '../widgets/note_inline_assistant_composer.dart';
import '../widgets/note_quill_editor.dart';
import '../widgets/note_tags_editor_sheet.dart';
import 'model_management_page.dart';
import 'note_share_composer_page.dart';

abstract interface class NoteEditorWriter {
  Future<Note> create(Note note);

  Future<Note> update(Note note);

  Future<void> deletePermanently(Note note);
}

final class RepositoryNoteEditorWriter implements NoteEditorWriter {
  RepositoryNoteEditorWriter(this.repository, {FileStorageService? storage})
    : storage = storage ?? FileStorageService.instance;

  final NoteRepository repository;
  final FileStorageService storage;

  @override
  Future<Note> create(Note note) => repository.create(note);

  @override
  Future<Note> update(Note note) => repository.update(note);

  @override
  Future<void> deletePermanently(Note note) async {
    await repository.deletePermanently(note.id);
    for (final asset in note.assets) {
      for (final key in [asset.storageKey, asset.previewStorageKey]) {
        try {
          await storage.deleteFile(key);
        } on FileSystemException {
          // The database deletion is authoritative. Orphan cleanup can retry
          // when a platform file handle is released.
        }
      }
    }
  }
}

typedef NoteEditorWriterLoader = Future<NoteEditorWriter> Function();

final class PickedNoteImage {
  const PickedNoteImage({required this.bytes, required this.originalName});

  final Uint8List bytes;
  final String originalName;
}

typedef NoteImagePicker = Future<PickedNoteImage?> Function(ImageSource source);
typedef NoteImageAssetImporter =
    Future<NoteAsset> Function(Uint8List bytes, {required String originalName});
typedef NoteReadAloudAvailabilityChecker = Future<bool> Function();
typedef NoteAssistantResultPresenter =
    Future<NoteAssistantResult?> Function(
      BuildContext context, {
      required NoteAssistantAction action,
      required NoteAssistantScope scope,
      required String title,
      required String content,
      required String languageCode,
      required Set<NoteAssistantPlacement> placements,
    });

abstract interface class NoteInlineAssistantDriver {
  Future<void> load();

  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request);

  Future<void> cancel();
}

final class LocalNoteInlineAssistantDriver
    implements NoteInlineAssistantDriver {
  LocalNoteInlineAssistantDriver([LocalAssistantService? assistant])
    : _assistant = assistant ?? LocalAssistantService.instance;

  final LocalAssistantService _assistant;

  @override
  Future<void> load() => _assistant.loadSelectedModel();

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) =>
      _assistant.generate(request);

  @override
  Future<void> cancel() => _assistant.cancel();
}

/// The clean-slate Delta editor route.
///
/// The page never converts its document to Markdown. Quill owns selection,
/// input, undo and formatting; persistence receives a validated snapshot only
/// after the debounce window or immediately before the route closes.
final class NoteQuillEditorPage extends StatefulWidget {
  const NoteQuillEditorPage({
    this.initialNote,
    this.writerLoader,
    this.importImage,
    this.pickImage,
    this.resolveImage,
    this.readAloud,
    this.readAloudAvailabilityChecker,
    this.assistantResultPresenter,
    this.inlineAssistantDriver,
    this.now,
    this.autosaveDelay = const Duration(milliseconds: 700),
    super.key,
  });

  final Note? initialNote;
  final NoteEditorWriterLoader? writerLoader;
  final NoteImageAssetImporter? importImage;
  final NoteImagePicker? pickImage;
  final NoteAssetImageProvider? resolveImage;
  final NoteReadAloudDriver? readAloud;
  final NoteReadAloudAvailabilityChecker? readAloudAvailabilityChecker;
  final NoteAssistantResultPresenter? assistantResultPresenter;
  final NoteInlineAssistantDriver? inlineAssistantDriver;
  final DateTime Function()? now;
  final Duration autosaveDelay;

  @override
  State<NoteQuillEditorPage> createState() => _NoteQuillEditorPageState();
}

final class _NoteQuillEditorPageState extends State<NoteQuillEditorPage>
    with WidgetsBindingObserver {
  late Note _note;
  late final NoteEditorController _editor;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _editorFocusNode;
  late final NoteImageAssetImporter _importImage;
  late final NoteEditorWriterLoader _writerLoader;
  late final NoteImagePicker _pickImage;
  late final NoteReadAloudDriver _readAloud;
  late final NoteInlineAssistantDriver _inlineAssistant;
  late final TextEditingController _inlineAssistantController;
  late final FocusNode _inlineAssistantFocusNode;
  late List<String> _tags;

  Timer? _autosaveTimer;
  Future<void> _saveTail = Future<void>.value();
  Future<void>? _imageImport;
  _EditorSaveState _saveState = _EditorSaveState.enabled;
  var _dirtyVersion = 0;
  var _savedVersion = 0;
  late String _observedTitle;
  var _importingImage = false;
  var _actionPending = false;
  var _closing = false;
  var _allowPop = false;
  var _inlineAssistantOpen = false;
  var _inlineAssistantLoading = false;
  var _inlineAssistantGenerating = false;
  var _inlineAssistantRunId = 0;
  String _inlineAssistantOutput = '';
  String? _inlineAssistantError;
  NoteAssistantInsertionSession? _inlineAssistantSession;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.initialNote ?? Note.newDraft(now: _now);
    _tags = [..._note.tags];
    _importImage =
        widget.importImage ?? NoteAssetImportService.instance.importImageBytes;
    _writerLoader =
        widget.writerLoader ??
        () async => RepositoryNoteEditorWriter(
          await NoteDatabaseService.instance.repository,
        );
    _pickImage = widget.pickImage ?? _pickImageFromDevice;
    _readAloud = widget.readAloud ?? NoteReadAloudService.instance;
    _inlineAssistant =
        widget.inlineAssistantDriver ?? LocalNoteInlineAssistantDriver();
    _inlineAssistantController = TextEditingController();
    _inlineAssistantFocusNode = FocusNode();
    _readAloud.addListener(_onReadAloudChanged);
    _observedTitle = _note.title;
    _titleController = TextEditingController(text: _note.title)
      ..addListener(_onTitleChanged);
    _titleFocusNode = FocusNode();
    _editorFocusNode = FocusNode();
    _editor = NoteEditorController(
      document: _note.document,
      assets: _note.assets,
      importImage: _importClipboardImage,
      discardImportedAsset: _deleteAssetFiles,
    )..addListener(_markDirty);
    _saveState = _note.revision == 0
        ? _EditorSaveState.enabled
        : _EditorSaveState.saved;
  }

  void _onTitleChanged() {
    final value = _titleController.text;
    if (value == _observedTitle) return;
    _observedTitle = value;
    _markDirty();
  }

  void _onReadAloudChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistLatest());
    }
  }

  void _markDirty() {
    if (!mounted) return;
    _dirtyVersion++;
    if (_saveState != _EditorSaveState.saving) {
      _saveState = _EditorSaveState.pending;
    }
    _autosaveTimer?.cancel();
    if (!_closing) {
      _autosaveTimer = Timer(widget.autosaveDelay, () {
        unawaited(_persistLatest());
      });
    }
    setState(() {});
  }

  Future<bool> _persistLatest() {
    _autosaveTimer?.cancel();
    final operation = _saveTail.then((_) => _persistCurrent());
    _saveTail = operation.then<void>((_) {});
    return operation;
  }

  Future<bool> _persistCurrent() async {
    if (_dirtyVersion == _savedVersion) return true;
    final targetVersion = _dirtyVersion;
    if (mounted) setState(() => _saveState = _EditorSaveState.saving);
    try {
      final candidate = _currentSnapshot(updatedAt: _now);

      if (candidate.revision == 0 && candidate.isMeaningfullyEmpty) {
        _savedVersion = targetVersion;
      } else {
        final writer = await _writerLoader();
        _note = candidate.revision == 0
            ? await writer.create(candidate)
            : await writer.update(candidate);
        _savedVersion = targetVersion;
      }
      if (mounted) {
        setState(() {
          _saveState = _dirtyVersion == _savedVersion
              ? _EditorSaveState.saved
              : _EditorSaveState.pending;
        });
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _saveState = _EditorSaveState.failed);
      return false;
    }
  }

  Note _currentSnapshot({DateTime? updatedAt}) {
    final snapshot = _editor.snapshot();
    final coverId = _note.coverAttachmentId;
    final retainedCover =
        coverId != null && snapshot.assets.any((asset) => asset.id == coverId);
    return _note.copyWith(
      title: _titleController.text.trim(),
      document: snapshot.document,
      tags: _tags,
      assets: snapshot.assets,
      coverAttachmentId: retainedCover ? coverId : null,
      updatedAt: updatedAt ?? _note.updatedAt,
    );
  }

  Future<void> _toggleReadAloud() async {
    if (_readAloud.isActive) {
      await _readAloud.stop();
      return;
    }
    if (_readAloud.status == ReadAloudStatus.failed) {
      await _readAloud.stop();
    }
    if (!await _ensureReadAloudAvailable() || !mounted) return;

    final text = NoteSemanticProjection.fromNote(
      _currentSnapshot(),
    ).speechText();
    if (text.trim().isEmpty) {
      AppFeedback.show(context, context.l10n.noteReadAloudFailed);
      return;
    }
    try {
      await _readAloud.speak(text);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(
        context,
        _readAloud.errorMessage ?? context.l10n.noteReadAloudFailed,
      );
    }
  }

  Future<bool> _ensureReadAloudAvailable() async {
    final checker = widget.readAloudAvailabilityChecker;
    if (checker != null) return checker();
    final model = await KokoroTtsModelService.instance.inspect();
    if (model.installed) return true;
    if (!mounted) return false;
    final openModels = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.offlineReadAloudModelRequired),
        content: Text(context.l10n.readAloudModelDownloadDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.maybeLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.manageModels),
          ),
        ],
      ),
    );
    if (openModels == true && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const ModelManagementPage(
            focusModelId: KokoroTtsModelService.modelId,
          ),
        ),
      );
    }
    return false;
  }

  bool get _inlineAssistantBusy =>
      _inlineAssistantLoading || _inlineAssistantGenerating;

  bool get _inlineAssistantReplacesSelection {
    final selection = _editor.quillController.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _toggleInlineAssistant() {
    if (_inlineAssistantBusy) return;
    if (_inlineAssistantOpen) {
      _closeInlineAssistant();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _inlineAssistantOpen = true;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
      _inlineAssistantSession = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineAssistantFocusNode.requestFocus();
    });
  }

  void _closeInlineAssistant() {
    if (_inlineAssistantBusy) return;
    _inlineAssistantRunId++;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _inlineAssistantOpen = false;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
      _inlineAssistantSession = null;
    });
    _editorFocusNode.requestFocus();
  }

  Future<void> _submitInlineAssistant(String rawInstruction) async {
    final instruction = rawInstruction.trim();
    if (instruction.isEmpty || _inlineAssistantBusy) return;
    _inlineAssistantController.text = instruction;
    FocusManager.instance.primaryFocus?.unfocus();
    final runId = ++_inlineAssistantRunId;
    setState(() {
      _inlineAssistantLoading = true;
      _inlineAssistantGenerating = false;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
    });

    if (widget.inlineAssistantDriver == null &&
        !await _ensureLanguageModelAvailable()) {
      if (mounted && runId == _inlineAssistantRunId) {
        setState(() => _inlineAssistantLoading = false);
      }
      return;
    }

    try {
      await _inlineAssistant.load();
      if (!mounted || runId != _inlineAssistantRunId) return;

      final anchor = _editor.captureAssistantAnchor();
      final session = _editor.beginAssistantInsertion();
      _inlineAssistantSession = session;
      final languageCode = Localizations.localeOf(context).languageCode;
      final projection = NoteSemanticProjection.fromNote(_currentSnapshot());
      final scope = anchor.hasSelection
          ? NoteAssistantScope.selection
          : NoteAssistantScope.fullNote;
      final request = NoteAssistantPromptBuilder.build(
        action: NoteAssistantAction.custom(instruction),
        title: _titleController.text.trim(),
        content: anchor.hasSelection
            ? anchor.selectedText
            : projection.assistantSource(languageCode: languageCode),
        scope: scope,
        languageCode: languageCode,
      );
      setState(() {
        _inlineAssistantLoading = false;
        _inlineAssistantGenerating = true;
      });

      final rawOutput = StringBuffer();
      var appliedOutput = '';
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final event in _inlineAssistant.generate(request)) {
        if (!mounted || runId != _inlineAssistantRunId) return;
        switch (event) {
          case LocalLlmTextDelta():
            rawOutput.write(event.text);
            final now = DateTime.now();
            if (now.difference(lastPaint) < const Duration(milliseconds: 70)) {
              continue;
            }
            final visible = LocalLlmOutputFilter.visibleText(
              rawOutput.toString(),
            );
            if (visible.trim().isEmpty || visible == appliedOutput) continue;
            if (!_editor.updateAssistantInsertion(session, visible)) {
              throw StateError(context.l10n.noteChangedRetryAssistant);
            }
            appliedOutput = visible;
            lastPaint = now;
            setState(() => _inlineAssistantOutput = visible);
          case LocalLlmGenerationCompleted():
            final visible = LocalLlmOutputFilter.visibleText(
              rawOutput.toString(),
            ).trim();
            if (visible.isNotEmpty && visible != appliedOutput) {
              if (!_editor.updateAssistantInsertion(session, visible)) {
                throw StateError(context.l10n.noteChangedRetryAssistant);
              }
              appliedOutput = visible;
            }
            _editor.finishAssistantInsertion(session);
            setState(() {
              _inlineAssistantOutput = visible;
              _inlineAssistantLoading = false;
              _inlineAssistantGenerating = false;
              if (visible.isEmpty) {
                _inlineAssistantError = context.l10n.assistantNoOutput;
              }
            });
        }
      }
      if (mounted &&
          runId == _inlineAssistantRunId &&
          _inlineAssistantGenerating) {
        _editor.finishAssistantInsertion(session);
        setState(() {
          _inlineAssistantLoading = false;
          _inlineAssistantGenerating = false;
          _inlineAssistantError = context.l10n.generationIncomplete;
        });
      }
    } catch (error) {
      if (!mounted || runId != _inlineAssistantRunId) return;
      final session = _inlineAssistantSession;
      if (session != null && _inlineAssistantOutput.trim().isEmpty) {
        _editor.revertAssistantInsertion(session);
        _inlineAssistantSession = null;
      } else if (session != null) {
        _editor.finishAssistantInsertion(session);
      }
      setState(() {
        _inlineAssistantLoading = false;
        _inlineAssistantGenerating = false;
        _inlineAssistantError = error.toString().replaceFirst(
          'Bad state: ',
          '',
        );
      });
    }
  }

  Future<void> _stopInlineAssistant() async {
    _inlineAssistantRunId++;
    try {
      await _inlineAssistant.cancel();
    } catch (_) {
      // The generation stream may already have reached its terminal event.
    }
    if (!mounted) return;
    final session = _inlineAssistantSession;
    if (session != null) _editor.finishAssistantInsertion(session);
    setState(() {
      _inlineAssistantLoading = false;
      _inlineAssistantGenerating = false;
      if (_inlineAssistantOutput.trim().isEmpty) {
        _inlineAssistantSession = null;
        _inlineAssistantOpen = false;
      }
    });
  }

  void _undoInlineAssistant() {
    final session = _inlineAssistantSession;
    if (session != null && !_editor.revertAssistantInsertion(session)) {
      AppFeedback.show(context, context.l10n.noteChangedRetryAssistant);
      return;
    }
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineAssistantFocusNode.requestFocus();
    });
  }

  void _continueInlineAssistant() {
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
      _inlineAssistantController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineAssistantFocusNode.requestFocus();
    });
  }

  void _retryInlineAssistant() {
    final instruction = _inlineAssistantController.text;
    final session = _inlineAssistantSession;
    if (session != null) _editor.revertAssistantInsertion(session);
    setState(() {
      _inlineAssistantSession = null;
      _inlineAssistantOutput = '';
      _inlineAssistantError = null;
    });
    unawaited(_submitInlineAssistant(instruction));
  }

  Future<void> _openLocalAssistant() async {
    try {
      final anchor = _editor.captureAssistantAnchor();
      final scopes = <NoteAssistantScope>{NoteAssistantScope.fullNote};
      if (anchor.hasCurrentLine) scopes.add(NoteAssistantScope.currentBlock);
      if (anchor.hasSelection) scopes.add(NoteAssistantScope.selection);
      final initialScope = anchor.hasSelection
          ? NoteAssistantScope.selection
          : anchor.hasCurrentLine
          ? NoteAssistantScope.currentBlock
          : NoteAssistantScope.fullNote;
      final invocation = await showNoteAssistantTaskSheet(
        context,
        availableScopes: scopes,
        initialScope: initialScope,
        allowChat: false,
      );
      if (invocation == null || !mounted || invocation.opensChat) return;

      final languageCode = Localizations.localeOf(context).languageCode;
      final projection = NoteSemanticProjection.fromNote(_currentSnapshot());
      final sourceContent = switch (invocation.scope) {
        NoteAssistantScope.selection => anchor.selectedText,
        NoteAssistantScope.currentBlock => anchor.currentLineText,
        NoteAssistantScope.fullNote => projection.assistantSource(
          languageCode: languageCode,
        ),
      };
      final placements = invocation.scope == NoteAssistantScope.fullNote
          ? const {
              NoteAssistantPlacement.replace,
              NoteAssistantPlacement.append,
            }
          : NoteAssistantPlacement.values.toSet();
      final presenter = widget.assistantResultPresenter ?? _presentAssistant;
      final generated = await presenter(
        context,
        action: invocation.action,
        scope: invocation.scope,
        title: invocation.scope == NoteAssistantScope.fullNote
            ? ''
            : _titleController.text.trim(),
        content: sourceContent,
        languageCode: languageCode,
        placements: placements,
      );
      if (generated == null || !mounted) return;

      final markdown = generated.placement == NoteAssistantPlacement.append
          ? '## ${_assistantResultHeading(invocation.action)}\n\n${generated.text}'
          : generated.text;
      final applied = _editor.applyAssistantMarkdown(
        anchor: anchor,
        scope: switch (invocation.scope) {
          NoteAssistantScope.selection => NoteAssistantEditScope.selection,
          NoteAssistantScope.currentBlock => NoteAssistantEditScope.currentLine,
          NoteAssistantScope.fullNote => NoteAssistantEditScope.document,
        },
        placement: switch (generated.placement) {
          NoteAssistantPlacement.replace => NoteAssistantEditPlacement.replace,
          NoteAssistantPlacement.insertBelow =>
            NoteAssistantEditPlacement.insertBelow,
          NoteAssistantPlacement.append => NoteAssistantEditPlacement.append,
        },
        markdown: markdown,
      );
      if (!applied) {
        AppFeedback.show(context, context.l10n.noteChangedRetryAssistant);
        return;
      }
      _editorFocusNode.requestFocus();
      AppFeedback.success(context, switch (generated.placement) {
        NoteAssistantPlacement.replace => context.l10n.assistantReplacedContent,
        NoteAssistantPlacement.insertBelow =>
          context.l10n.assistantInsertedBelow,
        NoteAssistantPlacement.append => context.l10n.assistantAppended,
      });
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.assistantLaunchFailed(error.toString()),
        );
      }
    }
  }

  Future<NoteAssistantResult?> _presentAssistant(
    BuildContext hostContext, {
    required NoteAssistantAction action,
    required NoteAssistantScope scope,
    required String title,
    required String content,
    required String languageCode,
    required Set<NoteAssistantPlacement> placements,
  }) async {
    if (!await _ensureLanguageModelAvailable() ||
        !mounted ||
        !hostContext.mounted) {
      return null;
    }
    return showModalBottomSheet<NoteAssistantResult>(
      context: hostContext,
      isScrollControlled: true,
      builder: (sheetContext) => NoteAssistantResultSheet(
        action: action,
        scope: scope,
        title: title,
        content: content,
        languageCode: languageCode,
        placements: placements,
      ),
    );
  }

  Future<bool> _ensureLanguageModelAvailable() async {
    final models = LanguageModelService.instance;
    final selectedId = await models.selectedModelId();
    final installed = await models.inspect(selectedId);
    if (installed.installed) return true;
    if (!mounted) return false;
    final downloadSize =
        '${(models.downloadSizeBytes(selectedId) / 1073741824).toStringAsFixed(1)} GB';
    final openModels = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.maybeLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.manageModels),
          ),
        ],
      ),
    );
    if (openModels != true || !mounted) return false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelManagementPage(focusModelId: selectedId),
      ),
    );
    if (!mounted) return false;
    final currentId = await models.selectedModelId();
    return (await models.inspect(currentId)).installed;
  }

  String _assistantResultHeading(NoteAssistantAction action) =>
      switch (action.task) {
        NoteAssistantTask.summarize => context.l10n.assistantSummaryHeading,
        NoteAssistantTask.extractTodos => context.l10n.assistantTodosHeading,
        NoteAssistantTask.polish => context.l10n.assistantPolishedHeading,
        null => context.l10n.assistantGeneratedHeading,
      };

  Future<void> _openShareComposer() async {
    await _imageImport;
    if (!mounted) return;
    final draft = NoteShareDraft.fromNote(_currentSnapshot());
    if (!draft.hasContent) {
      AppFeedback.show(context, context.l10n.noteHasNoShareableContent);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => NoteShareComposerPage(draft: draft)),
    );
  }

  Future<void> _editTags() async {
    final tags = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => NoteTagsEditorSheet(initialTags: _tags),
    );
    if (tags == null || !mounted || _sameTags(tags, _tags)) return;
    _tags = tags;
    _markDirty();
  }

  void _removeTag(String tag) {
    _tags = [..._tags]..remove(tag);
    _markDirty();
  }

  Future<bool> _updatePersistedMetadata(Note Function(Note note) change) async {
    if (_actionPending) return false;
    setState(() => _actionPending = true);
    try {
      await _imageImport;
      if (!await _persistLatest() || _note.revision == 0) {
        if (mounted && _saveState == _EditorSaveState.failed) {
          AppFeedback.error(context, context.l10n.saveFailedStorage);
        }
        return false;
      }
      final writer = await _writerLoader();
      _note = await writer.update(change(_note).copyWith(updatedAt: _now));
      if (mounted) setState(() => _saveState = _EditorSaveState.saved);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _saveState = _EditorSaveState.failed);
        AppFeedback.error(context, context.l10n.saveFailedStorage);
      }
      return false;
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<void> _togglePinned() async {
    await _updatePersistedMetadata(
      (note) => note.copyWith(isPinned: !note.isPinned),
    );
  }

  Future<void> _deleteNote() async {
    if (_note.revision == 0) {
      final confirmed = await _confirmDestructiveAction(
        title: context.l10n.discardNoteQuestion,
        description: context.l10n.discardNoteDescription,
        actionLabel: context.l10n.discardNote,
      );
      if (!confirmed || !mounted) return;
      setState(() => _actionPending = true);
      await _imageImport;
      await _discardUnsavedAssets();
      if (mounted) await _leaveEditor(null);
      return;
    }

    final confirmed = await _confirmDestructiveAction(
      title: context.l10n.deletePermanentlyQuestion,
      description: context.l10n.deletePermanentlyDescription,
      actionLabel: context.l10n.deletePermanently,
    );
    if (!confirmed || !mounted) return;
    setState(() => _actionPending = true);
    try {
      await _imageImport;
      if (!await _persistLatest()) return;
      final writer = await _writerLoader();
      await writer.deletePermanently(_note);
      if (mounted) await _leaveEditor(null);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.toolActionFailed(context.l10n.deletePermanently),
        );
      }
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String description,
    required String actionLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _leaveEditor(Note? result) async {
    if (!mounted) return;
    _autosaveTimer?.cancel();
    setState(() {
      _closing = true;
      _allowPop = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  void _handleMenuAction(_QuillEditorMenuAction action) {
    switch (action) {
      case _QuillEditorMenuAction.share:
        unawaited(_openShareComposer());
      case _QuillEditorMenuAction.tags:
        unawaited(_editTags());
      case _QuillEditorMenuAction.pin:
        unawaited(_togglePinned());
      case _QuillEditorMenuAction.save:
        unawaited(_persistLatest());
      case _QuillEditorMenuAction.delete:
        unawaited(_deleteNote());
    }
  }

  Future<NoteAsset?> _importClipboardImage(Uint8List bytes) async {
    try {
      return await _importImage(bytes, originalName: context.l10n.image);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.image),
        );
      }
      return null;
    }
  }

  Future<void> _showImageSourceSheet() async {
    if (_importingImage) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.addToNote,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ImageSourceAction(
                      key: const Key('quill-pick-gallery-image'),
                      icon: Icons.photo_library_outlined,
                      label: context.l10n.image,
                      onTap: () =>
                          Navigator.pop(sheetContext, ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ImageSourceAction(
                      key: const Key('quill-take-photo'),
                      icon: Icons.photo_camera_outlined,
                      label: context.l10n.camera,
                      onTap: () =>
                          Navigator.pop(sheetContext, ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final operation = _pickAndInsertImage(source);
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<void> _pickAndInsertImage(ImageSource source) async {
    setState(() => _importingImage = true);
    NoteAsset? imported;
    try {
      final selected = await _pickImage(source);
      if (selected == null || !mounted) return;
      imported = await _importImage(
        selected.bytes,
        originalName: selected.originalName,
      );
      if (!mounted) {
        await _deleteAssetFiles(imported);
        return;
      }
      _editor.insertAsset(imported);
      _editorFocusNode.requestFocus();
    } catch (_) {
      if (imported != null) await _deleteAssetFiles(imported);
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.attachmentImportTypeFailed(context.l10n.image),
        );
      }
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  static Future<PickedNoteImage?> _pickImageFromDevice(
    ImageSource source,
  ) async {
    final selected = await ImagePicker().pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (selected == null) return null;
    final byteLength = await selected.length();
    if (byteLength <= 0 || byteLength > 20 * 1024 * 1024) {
      throw const FormatException('图片文件为空或超过 20 MB');
    }
    return PickedNoteImage(
      bytes: await selected.readAsBytes(),
      originalName: selected.name,
    );
  }

  Future<void> _deleteAssetFiles(NoteAsset asset) async {
    await FileStorageService.instance.deleteFile(asset.storageKey);
    await FileStorageService.instance.deleteFile(asset.previewStorageKey);
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    setState(() => _closing = true);
    if (_inlineAssistantBusy) await _stopInlineAssistant();
    if (!mounted) return;
    await _imageImport;
    var saved = await _persistLatest();
    if (!mounted) return;

    if (!saved) {
      final action = await showDialog<_FailedSaveAction>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.autosaveFailedShort),
          content: Text(context.l10n.saveFailedStorage),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.keepEditing),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.discard),
              child: Text(context.l10n.discardDraft),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _FailedSaveAction.retry),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == _FailedSaveAction.retry) {
        saved = await _persistLatest();
      } else if (action == _FailedSaveAction.discard) {
        await _discardUnsavedAssets();
        saved = true;
      }
      if (!saved) {
        setState(() => _closing = false);
        return;
      }
    }

    final result = _note.revision == 0 ? null : _note;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _discardUnsavedAssets() async {
    final persistedIds = _note.revision == 0
        ? <NoteAttachmentId>{}
        : _note.assets.map((asset) => asset.id).toSet();
    for (final asset in _editor.assets) {
      if (!persistedIds.contains(asset.id)) await _deleteAssetFiles(asset);
    }
  }

  String _saveLabel(BuildContext context) => switch (_saveState) {
    _EditorSaveState.enabled => context.l10n.autosaveEnabled,
    _EditorSaveState.pending => context.l10n.autosavePending,
    _EditorSaveState.saving => context.l10n.autosaving,
    _EditorSaveState.saved => context.l10n.autosavedLocally,
    _EditorSaveState.failed => context.l10n.autosaveFailedShort,
  };

  IconData get _saveIcon => switch (_saveState) {
    _EditorSaveState.enabled => Icons.cloud_done_outlined,
    _EditorSaveState.pending => Icons.schedule_rounded,
    _EditorSaveState.saving => Icons.sync_rounded,
    _EditorSaveState.saved => Icons.check_circle_outline_rounded,
    _EditorSaveState.failed => Icons.error_outline_rounded,
  };

  Color get _saveColor => _saveState == _EditorSaveState.failed
      ? AppColors.danger
      : AppColors.muted;

  @override
  Widget build(BuildContext context) => PopScope<Note?>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: AbsorbPointer(
          absorbing: _actionPending,
          child: Column(
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 2),
                child: TextField(
                  key: const Key('quill-note-title'),
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  autofocus: _note.revision == 0,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  onSubmitted: (_) => _editorFocusNode.requestFocus(),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: 29,
                    height: 1.25,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.newNote,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              _buildTags(context),
              Expanded(
                child: NoteQuillEditor(
                  key: const Key('quill-note-body'),
                  controller: _editor,
                  focusNode: _editorFocusNode,
                  resolveImage: widget.resolveImage ?? _resolveManagedImage,
                  placeholder: context.l10n.noteStartHint,
                  readOnly:
                      _inlineAssistantBusy || _inlineAssistantSession != null,
                ),
              ),
              if (_importingImage)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: AppColors.accentSoft,
                ),
              if (_inlineAssistantOpen)
                NoteInlineAssistantComposer(
                  controller: _inlineAssistantController,
                  focusNode: _inlineAssistantFocusNode,
                  loading: _inlineAssistantLoading,
                  generating: _inlineAssistantGenerating,
                  hasResult:
                      _inlineAssistantSession != null &&
                      _inlineAssistantOutput.trim().isNotEmpty,
                  replacesSelection: _inlineAssistantReplacesSelection,
                  error: _inlineAssistantError,
                  onSubmit: (value) => unawaited(_submitInlineAssistant(value)),
                  onStop: () => unawaited(_stopInlineAssistant()),
                  onRetry: _retryInlineAssistant,
                  onUndo: _undoInlineAssistant,
                  onContinue: _continueInlineAssistant,
                  onClose: _closeInlineAssistant,
                )
              else
                NoteQuillToolbar(
                  controller: _editor,
                  onOpenAssistant: _toggleInlineAssistant,
                  onInsertImage: _showImageSourceSheet,
                  assistantTooltip: context.l10n.writeWithAi,
                  imageTooltip: context.l10n.image,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildTags(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in _tags)
            InputChip(
              key: ValueKey('quill-note-tag-$tag'),
              label: Text('#$tag'),
              onDeleted: () => _removeTag(tag),
              backgroundColor: AppColors.surfaceMuted,
              side: BorderSide.none,
              deleteIconColor: AppColors.subtle,
              visualDensity: VisualDensity.compact,
            ),
          ActionChip(
            key: const Key('quill-edit-tags'),
            avatar: const Icon(Icons.add_rounded, size: 17),
            label: Text(
              _tags.isEmpty ? context.l10n.addTags : context.l10n.tags,
            ),
            onPressed: _editTags,
            backgroundColor: _tags.isEmpty
                ? AppColors.surfaceMuted
                : Colors.transparent,
            side: BorderSide.none,
            labelStyle: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Row(
      children: [
        IconButton(
          key: const Key('quill-editor-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _closing ? null : _requestClose,
          style: IconButton.styleFrom(fixedSize: const Size.square(42)),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            key: const Key('quill-save-status'),
            onTap: _saveState == _EditorSaveState.failed
                ? () => unawaited(_persistLatest())
                : null,
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Row(
                key: ValueKey(_saveState),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_saveIcon, size: 14, color: _saveColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _saveLabel(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _saveColor,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_closing || _actionPending || _saveState == _EditorSaveState.saving)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...[
          IconButton(
            key: const Key('quill-local-assistant'),
            tooltip: context.l10n.localAssistant,
            onPressed: _inlineAssistantOpen ? null : _openLocalAssistant,
            style: IconButton.styleFrom(fixedSize: const Size.square(40)),
            icon: const Icon(Icons.auto_awesome_outlined, size: 21),
          ),
          IconButton(
            key: const Key('quill-read-aloud'),
            tooltip: _readAloud.isActive
                ? context.l10n.stopReadAloud
                : context.l10n.readAloud,
            onPressed: _toggleReadAloud,
            style: IconButton.styleFrom(fixedSize: const Size.square(40)),
            icon: _readAloud.status == ReadAloudStatus.generating
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _readAloud.isActive
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    size: 21,
                  ),
          ),
          AppAnchoredMenuButton<_QuillEditorMenuAction>(
            key: const Key('quill-editor-more'),
            tooltip: context.l10n.moreNoteActions,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _handleMenuAction,
            actions: _menuActions(context),
          ),
        ],
      ],
    ),
  );

  List<AppMenuAction<_QuillEditorMenuAction>> _menuActions(
    BuildContext context,
  ) => [
    AppMenuAction(
      value: _QuillEditorMenuAction.share,
      icon: Icons.ios_share_rounded,
      label: context.l10n.shareNoteAsImage,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.tags,
      icon: Icons.label_outline_rounded,
      label: context.l10n.tags,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.pin,
      icon: Icons.push_pin_outlined,
      label: _note.isPinned ? context.l10n.unpin : context.l10n.pin,
      selected: _note.isPinned,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.save,
      icon: Icons.save_outlined,
      label: context.l10n.save,
    ),
    AppMenuAction(
      value: _QuillEditorMenuAction.delete,
      icon: Icons.delete_outline_rounded,
      label: _note.revision == 0
          ? context.l10n.discardNote
          : context.l10n.deletePermanently,
      destructive: true,
    ),
  ];

  ImageProvider _resolveManagedImage(NoteAsset asset) => FileImage(
    File(FileStorageService.instance.absolutePath(asset.storageKey)),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inlineAssistantRunId++;
    if (_inlineAssistantBusy) unawaited(_inlineAssistant.cancel());
    _autosaveTimer?.cancel();
    _readAloud.removeListener(_onReadAloudChanged);
    if (_readAloud.isActive) unawaited(_readAloud.stop());
    _titleController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _inlineAssistantController.dispose();
    _inlineAssistantFocusNode.dispose();
    _editor.dispose();
    super.dispose();
  }
}

enum _EditorSaveState { enabled, pending, saving, saved, failed }

enum _FailedSaveAction { keepEditing, retry, discard }

enum _QuillEditorMenuAction { share, tags, pin, save, delete }

bool _sameTags(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _ImageSourceAction extends StatelessWidget {
  const _ImageSourceAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceMuted,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.accent),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    ),
  );
}
