import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_share.dart';
import '../services/file_storage_service.dart';
import '../services/note_share_image_service.dart';
import '../services/note_share_layout_engine.dart';
import '../services/note_share_preferences_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/note_share_page_canvas.dart';

typedef NoteShareFilesOverride = Future<void> Function(List<File> files);

class NoteShareComposerPage extends StatefulWidget {
  final NoteShareDraft draft;
  final NoteShareImageService imageService;
  final NoteShareFilesOverride? shareFilesOverride;

  const NoteShareComposerPage({
    super.key,
    required this.draft,
    this.imageService = const NoteShareImageService(),
    this.shareFilesOverride,
  });

  @override
  State<NoteShareComposerPage> createState() => _NoteShareComposerPageState();
}

class _NoteShareComposerPageState extends State<NoteShareComposerPage> {
  final _captureKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  final _layoutEngine = const NoteShareLayoutEngine();
  final _customWidth = TextEditingController(text: '1080');
  final _customHeight = TextEditingController(text: '1440');
  Timer? _preferenceSave;
  NoteShareOptions _options = const NoteShareOptions();
  NoteShareLayoutResult? _latestLayout;
  var _previewPageIndex = 0;
  var _renderPageIndex = 0;
  var _rendering = false;
  var _renderedPages = 0;
  var _totalPages = 0;
  var _optionsChangedBeforeLoad = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final loaded = await NoteSharePreferencesService.instance.load();
    if (!mounted || _optionsChangedBeforeLoad) return;
    setState(() {
      _options = loaded;
      _customWidth.text = loaded.canvas.customWidth.toString();
      _customHeight.text = loaded.canvas.customHeight.toString();
      _previewPageIndex = 0;
      _renderPageIndex = 0;
    });
  }

  @override
  void dispose() {
    _preferenceSave?.cancel();
    unawaited(NoteSharePreferencesService.instance.save(_options));
    _customWidth.dispose();
    _customHeight.dispose();
    super.dispose();
  }

  void _updateOptions(NoteShareOptions options) {
    if (_rendering) return;
    _optionsChangedBeforeLoad = true;
    setState(() {
      _options = options;
      _previewPageIndex = 0;
      _renderPageIndex = 0;
    });
    _preferenceSave?.cancel();
    _preferenceSave = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(NoteSharePreferencesService.instance.save(_options)),
    );
  }

  void _selectPreset(NoteShareCanvasPreset preset) {
    var orientation = _options.canvas.orientation;
    if (preset == NoteShareCanvasPreset.storyNineSixteen ||
        preset == NoteShareCanvasPreset.a4 ||
        preset == NoteShareCanvasPreset.long) {
      orientation = NoteShareOrientation.portrait;
    } else if (preset == NoteShareCanvasPreset.landscapeSixteenNine) {
      orientation = NoteShareOrientation.landscape;
    }
    _updateOptions(
      _options.copyWith(
        canvas: _options.canvas.copyWith(
          preset: preset,
          orientation: orientation,
        ),
      ),
    );
  }

  void _selectOrientation(NoteShareOrientation orientation) {
    if (_options.canvas.isLong || orientation == _options.canvas.orientation) {
      return;
    }
    var customWidth = _options.canvas.customWidth;
    var customHeight = _options.canvas.customHeight;
    if (_options.canvas.isCustom) {
      final shouldSwap =
          (orientation == NoteShareOrientation.portrait &&
              customWidth > customHeight) ||
          (orientation == NoteShareOrientation.landscape &&
              customWidth < customHeight);
      if (shouldSwap) {
        (customWidth, customHeight) = (customHeight, customWidth);
        _customWidth.text = customWidth.toString();
        _customHeight.text = customHeight.toString();
      }
    }
    _updateOptions(
      _options.copyWith(
        canvas: _options.canvas.copyWith(
          orientation: orientation,
          customWidth: customWidth,
          customHeight: customHeight,
        ),
      ),
    );
  }

  void _updateCustomSize() {
    final width = int.tryParse(_customWidth.text);
    final height = int.tryParse(_customHeight.text);
    if (width == null || height == null) return;
    final orientation = width > height
        ? NoteShareOrientation.landscape
        : NoteShareOrientation.portrait;
    _updateOptions(
      _options.copyWith(
        canvas: _options.canvas.copyWith(
          customWidth: width,
          customHeight: height,
          orientation: orientation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layout = _layoutEngine.paginate(
      draft: widget.draft,
      options: _options,
      textDirection: Directionality.of(context),
      untitledTitle: l10n.noteShareUntitled,
    );
    _latestLayout = layout;
    final pageIndex = _rendering
        ? _renderPageIndex.clamp(0, layout.pages.length - 1)
        : _previewPageIndex.clamp(0, layout.pages.length - 1);
    final pixelSize = layout.outputPixelSize;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.createShareImage)),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _previewPane(
                        context,
                        layout: layout,
                        pageIndex: pageIndex,
                        pixelSize: pixelSize,
                        standalone: true,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 4,
                      child: _controlsList(context, layout, pixelSize),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  _previewPane(
                    context,
                    layout: layout,
                    pageIndex: pageIndex,
                    pixelSize: pixelSize,
                  ),
                  const SizedBox(height: 24),
                  ..._controlSections(context),
                ],
              );
            },
          ),
          if (_rendering)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: layout.logicalWidth,
                    maxWidth: layout.logicalWidth,
                    minHeight: layout.logicalHeight,
                    maxHeight: layout.logicalHeight,
                    child: SizedBox(
                      width: layout.logicalWidth,
                      height: layout.logicalHeight,
                      child: RepaintBoundary(
                        key: _captureKey,
                        child: NoteSharePageCanvas(
                          draft: widget.draft,
                          options: _options,
                          layout: layout,
                          pageIndex: pageIndex,
                          untitledTitle: l10n.noteShareUntitled,
                          sourceLabel: l10n.noteShareSource,
                          locale: Localizations.localeOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_rendering)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.scrim,
                child: Center(
                  child: Container(
                    width: 250,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          l10n.generatingShareImageProgress(
                            math.min(_renderedPages + 1, _totalPages),
                            _totalPages,
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: FilledButton.icon(
            key: _shareButtonKey,
            onPressed: _rendering ? null : _generateAndShare,
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(l10n.generateAndShare),
          ),
        ),
      ),
    );
  }

  Widget _previewPane(
    BuildContext context, {
    required NoteShareLayoutResult layout,
    required int pageIndex,
    required NoteSharePixelSize pixelSize,
    bool standalone = false,
  }) {
    final l10n = context.l10n;
    final preview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '${pixelSize.width} × ${pixelSize.height}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Spacer(),
            Text(
              l10n.shareImagePageIndicator(pageIndex + 1, layout.pages.length),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const maxPreviewHeight = 520.0;
            final ratio = pixelSize.aspectRatio;
            final canvas = RepaintBoundary(
              child: NoteSharePageCanvas(
                draft: widget.draft,
                options: _options,
                layout: layout,
                pageIndex: pageIndex,
                untitledTitle: l10n.noteShareUntitled,
                sourceLabel: l10n.noteShareSource,
                locale: Localizations.localeOf(context),
              ),
            );
            if (_options.canvas.isLong) {
              final width = constraints.maxWidth;
              final scaledHeight = width / ratio;
              return Container(
                width: width,
                height: math.min(maxPreviewHeight, scaledHeight),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: SizedBox(
                    width: width,
                    height: scaledHeight,
                    child: FittedBox(
                      alignment: Alignment.topCenter,
                      fit: BoxFit.fitWidth,
                      child: canvas,
                    ),
                  ),
                ),
              );
            }
            final width = math.min(
              constraints.maxWidth,
              maxPreviewHeight * ratio,
            );
            final height = width / ratio;
            return SizedBox(
              width: width,
              height: height,
              child: FittedBox(fit: BoxFit.contain, child: canvas),
            );
          },
        ),
        const SizedBox(height: 10),
        if (_options.canvas.isLong)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.shareLongImageHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.previousPage,
                onPressed: _rendering || pageIndex <= 0
                    ? null
                    : () => setState(() {
                        _previewPageIndex = pageIndex - 1;
                        _renderPageIndex = _previewPageIndex;
                      }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${pageIndex + 1} / ${layout.pages.length}'),
              IconButton(
                tooltip: l10n.nextPage,
                onPressed: _rendering || pageIndex >= layout.pages.length - 1
                    ? null
                    : () => setState(() {
                        _previewPageIndex = pageIndex + 1;
                        _renderPageIndex = _previewPageIndex;
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
    if (!standalone) return preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      children: [preview],
    );
  }

  Widget _controlsList(
    BuildContext context,
    NoteShareLayoutResult layout,
    NoteSharePixelSize pixelSize,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
    children: _controlSections(context),
  );

  List<Widget> _controlSections(BuildContext context) {
    final l10n = context.l10n;
    return [
      _sectionTitle(l10n.shareImageStyle),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final template in NoteShareTemplateId.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: _options.template == template,
                  showCheckmark: false,
                  onSelected: _rendering
                      ? null
                      : (_) => _updateOptions(
                          _options.copyWith(template: template),
                        ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  label: Text(_templateLabel(l10n, template)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _sectionTitle(l10n.shareImageCanvas),
      DropdownButtonFormField<NoteShareCanvasPreset>(
        key: ValueKey(_options.canvas.preset),
        initialValue: _options.canvas.preset,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.shareImageRatio,
          prefixIcon: const Icon(Icons.aspect_ratio_rounded),
        ),
        items: [
          for (final preset in NoteShareCanvasPreset.values)
            DropdownMenuItem(
              value: preset,
              child: Text(_presetLabel(l10n, preset)),
            ),
        ],
        onChanged: _rendering
            ? null
            : (value) {
                if (value != null) _selectPreset(value);
              },
      ),
      const SizedBox(height: 12),
      SegmentedButton<NoteShareOrientation>(
        segments: [
          ButtonSegment(
            value: NoteShareOrientation.portrait,
            icon: const Icon(Icons.stay_current_portrait_rounded),
            label: Text(l10n.portraitOrientation),
          ),
          ButtonSegment(
            value: NoteShareOrientation.landscape,
            enabled: !_options.canvas.isLong,
            icon: const Icon(Icons.stay_current_landscape_rounded),
            label: Text(l10n.landscapeOrientation),
          ),
        ],
        selected: {_options.canvas.orientation},
        onSelectionChanged: _rendering
            ? null
            : (value) => _selectOrientation(value.first),
      ),
      if (_options.canvas.isCustom) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customWidth,
                enabled: !_rendering,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.shareImageWidth,
                  suffixText: 'px',
                ),
                onChanged: (_) => _updateCustomSize(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('×'),
            ),
            Expanded(
              child: TextField(
                controller: _customHeight,
                enabled: !_rendering,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.shareImageHeight,
                  suffixText: 'px',
                ),
                onChanged: (_) => _updateCustomSize(),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<NoteShareQuality>(
        key: ValueKey('${_options.canvas.quality}-${_options.canvas.isCustom}'),
        initialValue: _options.canvas.quality,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.shareImageQuality,
          prefixIcon: const Icon(Icons.high_quality_outlined),
        ),
        items: [
          for (final quality in NoteShareQuality.values)
            DropdownMenuItem(
              value: quality,
              child: Text(_qualityLabel(l10n, quality)),
            ),
        ],
        onChanged: _rendering || _options.canvas.isCustom
            ? null
            : (value) {
                if (value == null) return;
                _updateOptions(
                  _options.copyWith(
                    canvas: _options.canvas.copyWith(quality: value),
                  ),
                );
              },
      ),
      const SizedBox(height: 22),
      _sectionTitle(l10n.shareImageContent),
      _settingsCard([
        _toggle(
          context,
          icon: Icons.title_rounded,
          label: l10n.includeNoteTitle,
          value: _options.includeTitle,
          onChanged: (value) =>
              _updateOptions(_options.copyWith(includeTitle: value)),
        ),
        _toggle(
          context,
          icon: Icons.calendar_today_outlined,
          label: l10n.includeNoteDate,
          value: _options.includeDate,
          onChanged: (value) =>
              _updateOptions(_options.copyWith(includeDate: value)),
        ),
        _toggle(
          context,
          icon: Icons.tag_rounded,
          label: l10n.includeNoteTags,
          value: _options.includeTags,
          onChanged: widget.draft.tags.isEmpty
              ? null
              : (value) =>
                    _updateOptions(_options.copyWith(includeTags: value)),
        ),
        _toggle(
          context,
          icon: Icons.image_outlined,
          label: l10n.includeNoteImages,
          value: _options.includeImages,
          onChanged:
              widget.draft.attachments.any(
                (item) => item.kind == NoteAssetKind.image,
              )
              ? (value) =>
                    _updateOptions(_options.copyWith(includeImages: value))
              : null,
        ),
        _toggle(
          context,
          icon: Icons.attach_file_rounded,
          label: l10n.includeNoteAttachments,
          value: _options.includeAttachments,
          onChanged: widget.draft.attachments.isEmpty
              ? null
              : (value) => _updateOptions(
                  _options.copyWith(includeAttachments: value),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.verified_outlined, color: AppColors.moss),
          title: Text(l10n.noteShareSource),
          subtitle: Text(l10n.noteShareSourceAlwaysIncluded),
          trailing: const Icon(Icons.lock_outline_rounded, size: 18),
        ),
      ]),
      const SizedBox(height: 22),
      _sectionTitle(l10n.shareImageLayout),
      SegmentedButton<NoteShareDensity>(
        segments: [
          for (final density in NoteShareDensity.values)
            ButtonSegment(
              value: density,
              label: Text(_densityLabel(l10n, density)),
            ),
        ],
        selected: {_options.density},
        onSelectionChanged: _rendering
            ? null
            : (value) =>
                  _updateOptions(_options.copyWith(density: value.first)),
      ),
      const SizedBox(height: 16),
      Builder(
        builder: (context) {
          final layout = _latestLayout;
          final size = layout?.outputPixelSize;
          return Text(
            layout == null || size == null
                ? ''
                : l10n.shareImageOutputSummary(
                    layout.pages.length,
                    size.width,
                    size.height,
                  ),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          );
        },
      ),
    ];
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  Widget _settingsCard(List<Widget> children) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const Divider(height: 1),
        ],
      ],
    ),
  );

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile(
    secondary: Icon(icon),
    title: Text(label),
    value: value,
    onChanged: _rendering ? null : onChanged,
  );

  Future<void> _generateAndShare() async {
    final layout = _latestLayout;
    if (_rendering || layout == null) return;
    final l10n = context.l10n;
    final exportTitle = widget.draft.title.trim().isEmpty
        ? l10n.noteShareUntitled
        : widget.draft.title.trim();
    final originalPage = _previewPageIndex;
    setState(() {
      _rendering = true;
      _renderedPages = 0;
      _totalPages = layout.pages.length;
      _renderPageIndex = 0;
    });
    Directory? session;
    try {
      await _precacheImages();
      session = await widget.imageService.createSession();
      final files = <File>[];
      for (var index = 0; index < layout.pages.length; index++) {
        if (!mounted) return;
        setState(() => _renderPageIndex = index);
        await WidgetsBinding.instance.endOfFrame;
        final boundary = _captureKey.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary) {
          throw StateError('Share image boundary unavailable');
        }
        final output = layout.outputPixelSize;
        final pixelRatio = output.width / boundary.size.width;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) throw StateError('Share image encoding failed');
          files.add(
            await widget.imageService.writePage(
              session: session,
              bytes: bytes.buffer.asUint8List(),
              title: exportTitle,
              pageIndex: index,
              pageCount: layout.pages.length,
            ),
          );
        } finally {
          image.dispose();
        }
        if (mounted) setState(() => _renderedPages = index + 1);
      }
      if (!mounted) return;
      if (widget.shareFilesOverride != null) {
        await widget.shareFilesOverride!(files);
        await widget.imageService.deleteSession(session);
      } else {
        final box = _shareButtonKey.currentContext?.findRenderObject();
        final origin = box is RenderBox
            ? box.localToGlobal(Offset.zero) & box.size
            : null;
        final result = await widget.imageService.shareFiles(
          files: files,
          title: l10n.shareNoteImageTitle(exportTitle),
          sharePositionOrigin: origin,
        );
        if (result.status == ShareResultStatus.dismissed) {
          await widget.imageService.deleteSession(session);
        }
      }
    } catch (_) {
      if (session != null) await widget.imageService.deleteSession(session);
      if (mounted) {
        AppFeedback.error(context, context.l10n.shareImageGenerationFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _rendering = false;
          _previewPageIndex = originalPage.clamp(0, layout.pages.length - 1);
          _renderPageIndex = _previewPageIndex;
        });
      }
    }
  }

  Future<void> _precacheImages() async {
    if (!_options.includeAttachments || !_options.includeImages) return;
    for (final attachment in widget.draft.attachments) {
      if (attachment.kind != NoteAssetKind.image) continue;
      try {
        final path = FileStorageService.instance.absolutePath(
          attachment.storageKey,
        );
        await precacheImage(FileImage(File(path)), context);
      } catch (_) {
        // The renderer will show a neutral placeholder for unreadable images.
      }
    }
  }

  String _templateLabel(AppLocalizations l10n, NoteShareTemplateId template) =>
      switch (template) {
        NoteShareTemplateId.letter => l10n.shareTemplateLetter,
        NoteShareTemplateId.plain => l10n.shareTemplatePlain,
        NoteShareTemplateId.night => l10n.shareTemplateNight,
        NoteShareTemplateId.editorial => l10n.shareTemplateEditorial,
        NoteShareTemplateId.newspaper => l10n.shareTemplateNewspaper,
        NoteShareTemplateId.manuscript => l10n.shareTemplateManuscript,
        NoteShareTemplateId.botanical => l10n.shareTemplateBotanical,
        NoteShareTemplateId.blueprint => l10n.shareTemplateBlueprint,
        NoteShareTemplateId.amber => l10n.shareTemplateAmber,
        NoteShareTemplateId.film => l10n.shareTemplateFilm,
        NoteShareTemplateId.postcard => l10n.shareTemplatePostcard,
        NoteShareTemplateId.gallery => l10n.shareTemplateGallery,
        NoteShareTemplateId.neon => l10n.shareTemplateNeon,
        NoteShareTemplateId.tide => l10n.shareTemplateTide,
        NoteShareTemplateId.vermilion => l10n.shareTemplateVermilion,
      };

  String _presetLabel(AppLocalizations l10n, NoteShareCanvasPreset preset) =>
      switch (preset) {
        NoteShareCanvasPreset.square => l10n.shareRatioSquare,
        NoteShareCanvasPreset.portraitFourFive => l10n.shareRatioFourFive,
        NoteShareCanvasPreset.noteThreeFour => l10n.shareRatioThreeFour,
        NoteShareCanvasPreset.storyNineSixteen => l10n.shareRatioNineSixteen,
        NoteShareCanvasPreset.landscapeSixteenNine =>
          l10n.shareRatioSixteenNine,
        NoteShareCanvasPreset.a4 => l10n.shareRatioA4,
        NoteShareCanvasPreset.long => l10n.shareRatioLong,
        NoteShareCanvasPreset.custom => l10n.shareRatioCustom,
      };

  String _qualityLabel(AppLocalizations l10n, NoteShareQuality quality) =>
      switch (quality) {
        NoteShareQuality.standard => l10n.shareQualityStandard,
        NoteShareQuality.high => l10n.shareQualityHigh,
        NoteShareQuality.ultra => l10n.shareQualityUltra,
      };

  String _densityLabel(AppLocalizations l10n, NoteShareDensity density) =>
      switch (density) {
        NoteShareDensity.comfortable => l10n.shareDensityComfortable,
        NoteShareDensity.standard => l10n.shareDensityStandard,
        NoteShareDensity.compact => l10n.shareDensityCompact,
      };
}
