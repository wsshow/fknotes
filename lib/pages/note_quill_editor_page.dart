import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:quill_native_bridge/quill_native_bridge.dart';

import '../app.dart';
import '../debug/app_diagnostics.dart';
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
import '../services/note_audio_playback_service.dart';
import '../services/note_audio_recording_service.dart';
import '../services/note_asset_import_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/note_database_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_repository.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_attachment_title_sheet.dart';
import '../widgets/note_inline_assistant_composer.dart';
import '../widgets/note_external_image_drop.dart';
import '../widgets/note_quill_editor.dart';
import '../widgets/note_recording_bar.dart';
import '../widgets/quiet_paper.dart';
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
typedef NoteAudioAssetImporter =
    Future<NoteAsset> Function(
      File source, {
      required String originalName,
      required String displayName,
      required int durationMs,
    });
typedef NoteReadAloudAvailabilityChecker = Future<bool> Function();
typedef NoteLanguageModelAvailabilityChecker = Future<bool> Function();

/// The result returned when the note editor closes.
///
/// [completed] distinguishes the explicit toolbar action from system or
/// header back navigation so callers can return through intermediate routes.
final class NoteEditorRouteResult {
  const NoteEditorRouteResult({required this.note, required this.completed});

  final Note? note;
  final bool completed;
}

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
    this.importAudio,
    this.pickImage,
    this.resolveImage,
    this.resolveAssetPath,
    this.readAloud,
    this.readAloudAvailabilityChecker,
    this.inlineAssistantDriver,
    this.audioRecordingDriver,
    this.audioPlaybackDriver,
    this.languageModelAvailabilityChecker,
    this.now,
    this.autosaveDelay = const Duration(milliseconds: 700),
    super.key,
  });

  final Note? initialNote;
  final NoteEditorWriterLoader? writerLoader;
  final NoteImageAssetImporter? importImage;
  final NoteAudioAssetImporter? importAudio;
  final NoteImagePicker? pickImage;
  final NoteAssetImageProvider? resolveImage;
  final NoteAssetPathResolver? resolveAssetPath;
  final NoteReadAloudDriver? readAloud;
  final NoteReadAloudAvailabilityChecker? readAloudAvailabilityChecker;
  final NoteInlineAssistantDriver? inlineAssistantDriver;
  final NoteAudioRecordingDriver? audioRecordingDriver;
  final NoteAudioPlaybackDriver? audioPlaybackDriver;
  final NoteLanguageModelAvailabilityChecker? languageModelAvailabilityChecker;
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
  late final NoteAudioAssetImporter _importAudio;
  late final NoteEditorWriterLoader _writerLoader;
  late final NoteImagePicker _pickImage;
  late final NoteReadAloudDriver _readAloud;
  late final NoteInlineAssistantDriver _inlineAssistant;
  late final NoteAudioRecordingDriver _audioRecorder;
  late final NoteAudioPlaybackDriver _audioPlayback;
  late final TextEditingController _inlineAssistantController;
  late final FocusNode _inlineAssistantFocusNode;
  late List<String> _tags;

  Timer? _autosaveTimer;
  Future<void> _saveTail = Future<void>.value();
  Future<void>? _imageImport;
  Future<void>? _audioImport;
  StreamSubscription<double>? _recordingAmplitudeSubscription;
  Timer? _recordingTimer;
  _EditorSaveState _saveState = _EditorSaveState.enabled;
  var _dirtyVersion = 0;
  var _savedVersion = 0;
  late String _observedTitle;
  var _importingImage = false;
  var _actionPending = false;
  var _closing = false;
  var _allowPop = false;
  var _inlineAssistantOpen = false;
  var _inlineAssistantCheckingModel = false;
  var _inlineAssistantLoading = false;
  var _inlineAssistantGenerating = false;
  var _inlineAssistantRunId = 0;
  String _inlineAssistantOutput = '';
  String? _inlineAssistantError;
  NoteAssistantInsertionSession? _inlineAssistantSession;
  _NoteRecordingState _recordingState = _NoteRecordingState.idle;
  Duration _recordingElapsed = Duration.zero;
  List<double> _recordingAmplitudes = List<double>.filled(18, .06);
  final Stopwatch _recordingClock = Stopwatch();
  var _recordingRunId = 0;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  bool get _recordingVisible => _recordingState != _NoteRecordingState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.initialNote ?? Note.newDraft(now: _now);
    _tags = [..._note.tags];
    _importImage =
        widget.importImage ?? NoteAssetImportService.instance.importImageBytes;
    _importAudio =
        widget.importAudio ?? NoteAssetImportService.instance.importAudioFile;
    _writerLoader =
        widget.writerLoader ??
        () async => RepositoryNoteEditorWriter(
          await NoteDatabaseService.instance.repository,
        );
    _pickImage = widget.pickImage ?? _pickImageFromDevice;
    _readAloud = widget.readAloud ?? NoteReadAloudService.instance;
    _inlineAssistant =
        widget.inlineAssistantDriver ?? LocalNoteInlineAssistantDriver();
    _audioRecorder =
        widget.audioRecordingDriver ?? LocalNoteAudioRecordingDriver();
    _audioPlayback =
        widget.audioPlaybackDriver ?? LocalNoteAudioPlaybackDriver();
    _recordingAmplitudeSubscription = _audioRecorder.amplitudes.listen(
      _onRecordingAmplitude,
    );
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
      if (_recordingState == _NoteRecordingState.recording) {
        unawaited(_pauseOrResumeRecording());
      }
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
      final previous = _note;

      if (candidate.revision == 0 && candidate.isMeaningfullyEmpty) {
        _savedVersion = targetVersion;
      } else {
        final writer = await _writerLoader();
        _note = candidate.revision == 0
            ? await writer.create(candidate)
            : await writer.update(candidate);
        _savedVersion = targetVersion;
        await _discardRemovedAssetFiles(previous, _note);
      }
      if (mounted) {
        setState(() {
          _saveState = _dirtyVersion == _savedVersion
              ? _EditorSaveState.saved
              : _EditorSaveState.pending;
        });
      }
      return true;
    } catch (error, stackTrace) {
      AppDiagnostics.error(
        AppLogCategory.editor,
        'note_autosave_failed',
        data: {
          'revision': _note.revision,
          'dirtyVersion': _dirtyVersion,
          'savedVersion': _savedVersion,
          'assetCount': _editor.assets.length,
        },
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _saveState = _EditorSaveState.failed);
      return false;
    }
  }

  Future<void> _discardRemovedAssetFiles(Note previous, Note current) async {
    final retained = current.assetsById;
    for (final asset in previous.assets) {
      final replacement = retained[asset.id];
      if (replacement == null ||
          replacement.storageKey != asset.storageKey ||
          replacement.previewStorageKey != asset.previewStorageKey) {
        await _deleteAssetFilesBestEffort(asset);
      }
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
      _inlineAssistantCheckingModel ||
      _inlineAssistantLoading ||
      _inlineAssistantGenerating;

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
    final availabilityChecker = widget.languageModelAvailabilityChecker;
    final shouldCheckAvailability =
        availabilityChecker != null || widget.inlineAssistantDriver == null;
    setState(() {
      _inlineAssistantCheckingModel = shouldCheckAvailability;
      _inlineAssistantLoading = !shouldCheckAvailability;
      _inlineAssistantGenerating = false;
      _inlineAssistantError = null;
      _inlineAssistantOutput = '';
    });

    try {
      if (shouldCheckAvailability) {
        final available =
            await (availabilityChecker?.call() ??
                _ensureLanguageModelAvailable());
        if (!mounted || runId != _inlineAssistantRunId) return;
        if (!available) {
          setState(() => _inlineAssistantCheckingModel = false);
          return;
        }
        setState(() {
          _inlineAssistantCheckingModel = false;
          _inlineAssistantLoading = true;
        });
      }

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
        _inlineAssistantCheckingModel = false;
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
      _inlineAssistantCheckingModel = false;
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
      final asset = await _importImage(bytes, originalName: context.l10n.image);
      _editorFocusNode.unfocus();
      return asset;
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
      _editorFocusNode.unfocus();
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

  Future<void> _handleDroppedImages(
    NoteDroppedImageBatch batch,
    int documentOffset,
  ) async {
    final operation = (_imageImport ?? Future<void>.value()).then(
      (_) => _importDroppedImages(batch, documentOffset),
    );
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<void> _importDroppedImages(
    NoteDroppedImageBatch batch,
    int documentOffset,
  ) async {
    if (batch.images.isEmpty) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.onlyImagesCanBeDropped);
      }
      return;
    }
    setState(() => _importingImage = true);
    var insertionOffset = documentOffset;
    var importFailures = 0;
    try {
      for (final image in batch.images) {
        NoteAsset? imported;
        try {
          imported = await _importImage(
            image.bytes,
            originalName: image.originalName,
          );
          if (!mounted) {
            await _deleteAssetFilesBestEffort(imported);
            return;
          }
          _editor.insertAssetAt(imported, insertionOffset);
          insertionOffset += 2;
          imported = null;
        } catch (_) {
          importFailures++;
          if (imported != null) await _deleteAssetFilesBestEffort(imported);
        }
      }
      if (!mounted) return;
      _editorFocusNode.unfocus();
      if (batch.rejectedCount > 0) {
        AppFeedback.error(context, context.l10n.droppedImagesRejected);
      } else if (importFailures > 0) {
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

  Future<void> _copyImage(NoteAsset asset) async {
    try {
      final bridge = QuillNativeBridge();
      if (!await bridge.isSupported(
        QuillNativeBridgeFeature.copyImageToClipboard,
      )) {
        if (mounted) {
          AppFeedback.show(context, context.l10n.imageCopyUnavailable);
        }
        return;
      }
      final path = FileStorageService.instance.absolutePath(asset.storageKey);
      await bridge.copyImageToClipboard(await File(path).readAsBytes());
      if (mounted) AppFeedback.success(context, context.l10n.imageCopied);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.imageCopyFailed);
    }
  }

  Future<void> _editImage(NoteAsset requestedAsset) async {
    final current = _editor.asset(requestedAsset.id);
    if (current == null || !mounted) return;
    final action = await showModalBottomSheet<_ImageEditAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.renameAttachment),
              onTap: () => Navigator.pop(sheetContext, _ImageEditAction.rename),
            ),
            ListTile(
              key: const Key('replace-image-from-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.l10n.replaceFromGallery),
              onTap: () =>
                  Navigator.pop(sheetContext, _ImageEditAction.gallery),
            ),
            ListTile(
              key: const Key('replace-image-from-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.l10n.replaceWithCamera),
              onTap: () => Navigator.pop(sheetContext, _ImageEditAction.camera),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ImageEditAction.rename:
        await _renameImage(current);
      case _ImageEditAction.gallery:
        await _replaceImage(current, ImageSource.gallery);
      case _ImageEditAction.camera:
        await _replaceImage(current, ImageSource.camera);
    }
  }

  Future<void> _renameImage(NoteAsset requestedAsset) async {
    final result = await showNoteAttachmentTitleSheet(
      context,
      initialValue: requestedAsset.displayTitle,
      fieldKey: const Key('image-attachment-title'),
    );
    if (result == null || !mounted) return;
    final current = _editor.asset(requestedAsset.id);
    if (current == null) return;
    _editor.updateAsset(
      current.copyWith(displayName: result.displayName, updatedAt: _now),
    );
  }

  Future<void> _replaceImage(
    NoteAsset requestedAsset,
    ImageSource source,
  ) async {
    if (_importingImage) return;
    final operation = _replaceImageFiles(requestedAsset, source);
    _imageImport = operation;
    await operation;
    if (identical(_imageImport, operation)) _imageImport = null;
  }

  Future<void> _replaceImageFiles(
    NoteAsset requestedAsset,
    ImageSource source,
  ) async {
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
      final current = _editor.asset(requestedAsset.id);
      if (current == null) {
        await _deleteAssetFiles(imported);
        return;
      }
      final replacement = NoteAsset(
        id: current.id,
        kind: NoteAssetKind.image,
        storageKey: imported.storageKey,
        originalName: imported.originalName,
        displayName: current.displayName,
        byteLength: imported.byteLength,
        mimeType: imported.mimeType,
        previewStorageKey: imported.previewStorageKey,
        createdAt: current.createdAt,
        updatedAt: _now,
      );
      _editor.updateAsset(replacement);
      if (!await _persistLatest()) {
        _editor.updateAsset(current);
        await _deleteAssetFilesBestEffort(imported);
        if (mounted) {
          AppFeedback.error(context, context.l10n.imageReplaceFailed);
        }
        return;
      }
      if (mounted) AppFeedback.success(context, context.l10n.imageReplaced);
    } catch (_) {
      if (imported != null) await _deleteAssetFilesBestEffort(imported);
      if (mounted) {
        AppFeedback.error(context, context.l10n.imageReplaceFailed);
      }
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  Future<void> _showImageDetails(NoteAsset requestedAsset) async {
    final asset = _editor.asset(requestedAsset.id);
    if (asset == null || !mounted) return;
    final imageProvider = (widget.resolveImage ?? _resolveManagedImage)(asset);
    final formatter = DateFormat.yMMMd(context.l10n.localeName).add_Hm();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: (MediaQuery.sizeOf(sheetContext).height * .78).clamp(
          420.0,
          680.0,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          children: [
            Text(
              context.l10n.imageDetails,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            if (imageProvider != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: ColoredBox(
                  color: AppColors.surfaceMuted,
                  child: Image(
                    image: imageProvider,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            if (imageProvider != null) const SizedBox(height: 18),
            _ImageDetailRow(
              label: context.l10n.fileName,
              value: asset.originalName,
            ),
            _ImageDetailRow(label: context.l10n.type, value: asset.mimeType),
            _ImageDetailRow(
              label: context.l10n.size,
              value: _formatBytes(asset.byteLength),
            ),
            _ImageDetailRow(
              label: context.l10n.created,
              value: formatter.format(asset.createdAt.toLocal()),
            ),
            _ImageDetailRow(
              label: context.l10n.updated,
              value: formatter.format(asset.updatedAt.toLocal()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewOriginalImage(NoteAsset requestedAsset) async {
    final asset = _editor.asset(requestedAsset.id);
    if (asset == null || !mounted) return;
    final imageProvider = (widget.resolveImage ?? _resolveManagedImage)(asset);
    if (imageProvider == null) {
      AppFeedback.error(context, context.l10n.originalFileMissing);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (viewerContext) => _OriginalImageViewer(
          imageProvider: imageProvider,
          title: asset.displayTitle,
        ),
      ),
    );
  }

  Future<void> _deleteAssetFilesBestEffort(NoteAsset asset) async {
    try {
      await _deleteAssetFiles(asset);
    } catch (_) {
      // Persistence is authoritative; abandoned files can be reclaimed by a
      // later storage cleanup if the platform still has an open handle.
    }
  }

  void _onRecordingAmplitude(double amplitude) {
    if (!mounted || _recordingState != _NoteRecordingState.recording) return;
    setState(() {
      _recordingAmplitudes = [
        ..._recordingAmplitudes.skip(1),
        amplitude.clamp(.06, 1.0),
      ];
    });
  }

  Future<void> _startRecording() async {
    if (_recordingVisible || _actionPending || _closing) return;
    final runId = ++_recordingRunId;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_readAloud.isActive) await _readAloud.stop();
    if (!mounted || runId != _recordingRunId) return;
    setState(() {
      _recordingState = _NoteRecordingState.preparing;
      _recordingElapsed = Duration.zero;
      _recordingAmplitudes = List<double>.filled(18, .06);
    });
    try {
      await _audioRecorder.start();
      if (!mounted || runId != _recordingRunId) {
        await _audioRecorder.cancel();
        return;
      }
      _recordingClock
        ..reset()
        ..start();
      _startRecordingTimer();
      setState(() => _recordingState = _NoteRecordingState.recording);
    } on NoteMicrophonePermissionDenied {
      _resetRecordingUi();
      await _showMicrophonePermissionDialog();
    } catch (error) {
      await _audioRecorder.cancel();
      _resetRecordingUi();
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingStartFailed(_readableError(error)),
        );
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recordingClock.isRunning) return;
      setState(() => _recordingElapsed = _recordingClock.elapsed);
    });
  }

  Future<void> _pauseOrResumeRecording() async {
    try {
      if (_recordingState == _NoteRecordingState.recording) {
        await _audioRecorder.pause();
        _recordingClock.stop();
        _recordingTimer?.cancel();
        _recordingElapsed = _recordingClock.elapsed;
        if (mounted) {
          setState(() => _recordingState = _NoteRecordingState.paused);
        }
      } else if (_recordingState == _NoteRecordingState.paused) {
        await _audioRecorder.resume();
        _recordingClock.start();
        _startRecordingTimer();
        if (mounted) {
          setState(() => _recordingState = _NoteRecordingState.recording);
        }
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingStartFailed(_readableError(error)),
        );
      }
    }
  }

  Future<void> _finishRecording() async {
    if (_recordingState != _NoteRecordingState.recording &&
        _recordingState != _NoteRecordingState.paused) {
      return;
    }
    _recordingElapsed = _recordingClock.elapsed;
    final runId = _recordingRunId;
    _recordingClock.stop();
    _recordingTimer?.cancel();
    setState(() => _recordingState = _NoteRecordingState.saving);
    final operation = _saveRecording(runId);
    _audioImport = operation;
    await operation;
    if (identical(_audioImport, operation)) _audioImport = null;
  }

  Future<void> _saveRecording(int runId) async {
    File? temporaryFile;
    NoteAsset? imported;
    try {
      final recording = await _audioRecorder.stop();
      temporaryFile = File(recording.path);
      if (!mounted || runId != _recordingRunId) return;
      final timestamp = _now;
      final local = timestamp.toLocal();
      final originalName = 'recording-${timestamp.microsecondsSinceEpoch}.m4a';
      final displayName = context.l10n.voiceNoteDefaultTitle(
        '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}',
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}',
      );
      imported = await _importAudio(
        temporaryFile,
        originalName: originalName,
        displayName: displayName,
        durationMs: _recordingElapsed.inMilliseconds,
      );
      if (!mounted || runId != _recordingRunId) {
        await _deleteAssetFiles(imported);
        return;
      }
      _editor.insertAsset(imported);
      _resetRecordingUi();
      _editorFocusNode.unfocus();
      AppFeedback.success(context, context.l10n.recordingAdded);
    } catch (error) {
      if (imported != null) await _deleteAssetFiles(imported);
      await _audioRecorder.cancel();
      _resetRecordingUi();
      if (mounted) {
        AppFeedback.error(
          context,
          context.l10n.recordingSaveFailed(_readableError(error)),
        );
      }
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recordingVisible || _recordingState == _NoteRecordingState.saving) {
      return;
    }
    _recordingRunId++;
    _recordingClock.stop();
    _recordingTimer?.cancel();
    try {
      await _audioRecorder.cancel();
    } finally {
      _resetRecordingUi();
    }
  }

  void _resetRecordingUi() {
    _recordingClock
      ..stop()
      ..reset();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (!mounted) return;
    setState(() {
      _recordingState = _NoteRecordingState.idle;
      _recordingElapsed = Duration.zero;
      _recordingAmplitudes = List<double>.filled(18, .06);
    });
  }

  Future<void> _showMicrophonePermissionDialog() async {
    if (!mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.microphonePermissionRequired),
        content: Text(context.l10n.microphonePermissionDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.openSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) await permissions.openAppSettings();
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _readableError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state: |StateError: |Exception: )'),
    '',
  );

  Future<void> _requestClose({bool completed = false}) async {
    if (_closing) return;
    setState(() => _closing = true);
    if (_inlineAssistantBusy) await _stopInlineAssistant();
    if (!mounted) return;
    if (_recordingState == _NoteRecordingState.saving) {
      await _audioImport;
    } else if (_recordingVisible) {
      final discard = await _confirmDestructiveAction(
        title: context.l10n.discardRecordingQuestion,
        description: context.l10n.discardRecordingDescription,
        actionLabel: context.l10n.discard,
      );
      if (!discard || !mounted) {
        if (mounted) setState(() => _closing = false);
        return;
      }
      await _cancelRecording();
    }
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

    final result = NoteEditorRouteResult(
      note: _note.revision == 0 ? null : _note,
      completed: completed,
    );
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
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: PaperShell(
          child: AbsorbPointer(
            absorbing: _actionPending,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 7, 12, 0),
                    decoration: BoxDecoration(
                      color: AppColors.paperPrimary,
                      border: Border.all(color: AppColors.line),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.small),
                      ),
                      boxShadow: AppShadows.paperEdge,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 21, 24, 2),
                          child: TextField(
                            key: const Key('quill-note-title'),
                            controller: _titleController,
                            focusNode: _titleFocusNode,
                            autofocus: _note.revision == 0,
                            readOnly: _recordingVisible,
                            maxLines: 1,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(200),
                            ],
                            onSubmitted: (_) => _editorFocusNode.requestFocus(),
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontSize: 29, height: 1.25),
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 5, 24, 0),
                          child: Container(
                            height: 1,
                            color: AppColors.mechanicalBlue.withValues(
                              alpha: .42,
                            ),
                          ),
                        ),
                        Expanded(
                          child: NoteQuillEditor(
                            key: const Key('quill-note-body'),
                            controller: _editor,
                            focusNode: _editorFocusNode,
                            resolveImage:
                                widget.resolveImage ?? _resolveManagedImage,
                            resolveAssetPath:
                                widget.resolveAssetPath ??
                                _resolveManagedAssetPath,
                            audioPlayback: _audioPlayback,
                            onCopyImage: _copyImage,
                            onEditImage: _editImage,
                            onViewImageOriginal: _viewOriginalImage,
                            onShowImageDetails: _showImageDetails,
                            onDropImages: _handleDroppedImages,
                            placeholder: context.l10n.noteStartHint,
                            readOnly:
                                _inlineAssistantBusy ||
                                _inlineAssistantSession != null ||
                                _recordingVisible,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_importingImage)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.accent,
                    backgroundColor: AppColors.accentSoft,
                  ),
                if (_recordingVisible)
                  NoteRecordingBar(
                    preparing: _recordingState == _NoteRecordingState.preparing,
                    saving: _recordingState == _NoteRecordingState.saving,
                    paused: _recordingState == _NoteRecordingState.paused,
                    elapsed: _recordingElapsed,
                    amplitudes: _recordingAmplitudes,
                    onCancel: _recordingState == _NoteRecordingState.saving
                        ? null
                        : () => unawaited(_cancelRecording()),
                    onPauseOrResume:
                        _recordingState == _NoteRecordingState.recording ||
                            _recordingState == _NoteRecordingState.paused
                        ? () => unawaited(_pauseOrResumeRecording())
                        : null,
                    onFinish:
                        _recordingState == _NoteRecordingState.recording ||
                            _recordingState == _NoteRecordingState.paused
                        ? () => unawaited(_finishRecording())
                        : null,
                  )
                else if (_inlineAssistantOpen)
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
                    onSubmit: (value) =>
                        unawaited(_submitInlineAssistant(value)),
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
                    onRecordAudio: () => unawaited(_startRecording()),
                    onDone: _closing
                        ? null
                        : () => unawaited(_requestClose(completed: true)),
                    assistantTooltip: context.l10n.writeWithAi,
                    imageTooltip: context.l10n.image,
                    recordTooltip: context.l10n.record,
                    doneLabel: context.l10n.finishEditing,
                  ),
              ],
            ),
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
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppColors.line),
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
            backgroundColor: Colors.transparent,
            side: const BorderSide(color: AppColors.line),
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

  Widget _buildHeader(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    decoration: const BoxDecoration(
      color: AppColors.paperSecondary,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
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
            key: const Key('quill-read-aloud'),
            tooltip: _readAloud.isActive
                ? context.l10n.stopReadAloud
                : context.l10n.readAloud,
            onPressed: _recordingVisible ? null : _toggleReadAloud,
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
            enabled: !_recordingVisible,
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

  String _resolveManagedAssetPath(NoteAsset asset) =>
      FileStorageService.instance.absolutePath(asset.storageKey);

  Future<void> _disposeAudioRecorder() async {
    await _recordingAmplitudeSubscription?.cancel();
    _recordingAmplitudeSubscription = null;
    await _audioRecorder.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inlineAssistantRunId++;
    if (_inlineAssistantBusy) unawaited(_inlineAssistant.cancel());
    _autosaveTimer?.cancel();
    _recordingTimer?.cancel();
    unawaited(_disposeAudioRecorder());
    _audioPlayback.dispose();
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

enum _NoteRecordingState { idle, preparing, recording, paused, saving }

enum _FailedSaveAction { keepEditing, retry, discard }

enum _QuillEditorMenuAction { share, tags, pin, save, delete }

enum _ImageEditAction { rename, gallery, camera }

bool _sameTags(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

final class _OriginalImageViewer extends StatelessWidget {
  const _OriginalImageViewer({
    required this.imageProvider,
    required this.title,
  });

  final ImageProvider imageProvider;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          minScale: .75,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Image(
              key: const Key('note-original-image'),
              image: imageProvider,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ImageDetailRow extends StatelessWidget {
  const _ImageDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
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
