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
import '../models/note.dart';
import '../models/note_share.dart';
import '../models/note_semantic_projection.dart';
import '../services/file_storage_service.dart';
import '../services/kokoro_tts_model_service.dart';
import '../services/language_model_service.dart';
import '../services/local_model_manager.dart';
import '../services/note_asset_import_service.dart';
import '../services/note_assistant_prompt_builder.dart';
import '../services/note_database_service.dart';
import '../services/note_read_aloud_service.dart';
import '../services/note_repository.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/note_assistant_sheet.dart';
import '../widgets/note_quill_editor.dart';
import 'model_management_page.dart';
import 'note_share_composer_page.dart';

abstract interface class NoteEditorWriter {
  Future<Note> create(Note note);

  Future<Note> update(Note note);
}

final class RepositoryNoteEditorWriter implements NoteEditorWriter {
  const RepositoryNoteEditorWriter(this.repository);

  final NoteRepository repository;

  @override
  Future<Note> create(Note note) => repository.create(note);

  @override
  Future<Note> update(Note note) => repository.update(note);
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

  Timer? _autosaveTimer;
  Future<void> _saveTail = Future<void>.value();
  Future<void>? _imageImport;
  _EditorSaveState _saveState = _EditorSaveState.enabled;
  var _dirtyVersion = 0;
  var _savedVersion = 0;
  late String _observedTitle;
  var _importingImage = false;
  var _closing = false;
  var _allowPop = false;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.initialNote ?? Note.newDraft(now: _now);
    _importImage =
        widget.importImage ?? NoteAssetImportService.instance.importImageBytes;
    _writerLoader =
        widget.writerLoader ??
        () async => RepositoryNoteEditorWriter(
          await NoteDatabaseService.instance.repository,
        );
    _pickImage = widget.pickImage ?? _pickImageFromDevice;
    _readAloud = widget.readAloud ?? NoteReadAloudService.instance;
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

  void _handleMenuAction(_QuillEditorMenuAction action) {
    switch (action) {
      case _QuillEditorMenuAction.share:
        unawaited(_openShareComposer());
      case _QuillEditorMenuAction.save:
        unawaited(_persistLatest());
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
    final persistedIds = _note.assets.map((asset) => asset.id).toSet();
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

  Color get _saveColor =>
      _saveState == _EditorSaveState.failed ? AppColors.coral : AppColors.muted;

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
        child: Column(
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 2),
              child: TextField(
                key: const Key('quill-note-title'),
                controller: _titleController,
                focusNode: _titleFocusNode,
                autofocus: _note.revision == 0,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                onSubmitted: (_) => _editorFocusNode.requestFocus(),
                style: Theme.of(context).textTheme.headlineLarge,
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
            Expanded(
              child: NoteQuillEditor(
                key: const Key('quill-note-body'),
                controller: _editor,
                focusNode: _editorFocusNode,
                resolveImage: widget.resolveImage ?? _resolveManagedImage,
                placeholder: context.l10n.noteStartHint,
              ),
            ),
            if (_importingImage)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.coral,
                backgroundColor: AppColors.softCoral,
              ),
            NoteQuillToolbar(
              controller: _editor,
              onInsertImage: _showImageSourceSheet,
              imageTooltip: context.l10n.image,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 18, 0),
    child: Row(
      children: [
        IconButton(
          key: const Key('quill-editor-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _closing ? null : _requestClose,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _note.revision == 0
                    ? context.l10n.newNote
                    : context.l10n.editNote,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 1),
              InkWell(
                key: const Key('quill-save-status'),
                onTap: _saveState == _EditorSaveState.failed
                    ? () => unawaited(_persistLatest())
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Row(
                    key: ValueKey(_saveState),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_saveIcon, size: 13, color: _saveColor),
                      const SizedBox(width: 5),
                      Text(
                        _saveLabel(context),
                        style: TextStyle(
                          color: _saveColor,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_closing || _saveState == _EditorSaveState.saving)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...[
          IconButton(
            key: const Key('quill-local-assistant'),
            tooltip: context.l10n.localAssistant,
            onPressed: _openLocalAssistant,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            key: const Key('quill-read-aloud'),
            tooltip: _readAloud.isActive
                ? context.l10n.stopReadAloud
                : context.l10n.readAloud,
            onPressed: _toggleReadAloud,
            icon: _readAloud.status == ReadAloudStatus.generating
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _readAloud.isActive
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                  ),
          ),
          AppAnchoredMenuButton<_QuillEditorMenuAction>(
            key: const Key('quill-editor-more'),
            tooltip: context.l10n.moreNoteActions,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _handleMenuAction,
            actions: [
              AppMenuAction(
                value: _QuillEditorMenuAction.share,
                icon: Icons.ios_share_rounded,
                label: context.l10n.shareNoteAsImage,
              ),
              AppMenuAction(
                value: _QuillEditorMenuAction.save,
                icon: Icons.save_outlined,
                label: context.l10n.save,
              ),
            ],
          ),
        ],
      ],
    ),
  );

  ImageProvider _resolveManagedImage(NoteAsset asset) => FileImage(
    File(FileStorageService.instance.absolutePath(asset.storageKey)),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _readAloud.removeListener(_onReadAloudChanged);
    if (_readAloud.isActive) unawaited(_readAloud.stop());
    _titleController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _editor.dispose();
    super.dispose();
  }
}

enum _EditorSaveState { enabled, pending, saving, saved, failed }

enum _FailedSaveAction { keepEditing, retry, discard }

enum _QuillEditorMenuAction { share, save }

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
    color: AppColors.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.coral),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    ),
  );
}
