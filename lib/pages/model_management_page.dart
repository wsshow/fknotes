import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../l10n/local_model_l10n.dart';
import '../models/local_model.dart';
import '../services/model_download_source_policy.dart';
import '../services/local_model_manager.dart';
import '../services/realtime_dictation_preferences_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/editor_context_menu.dart';
import 'taobao_mnn_catalog_page.dart';

class ModelManagementPage extends StatefulWidget {
  final String? focusModelId;
  const ModelManagementPage({super.key, this.focusModelId});

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  final _manager = LocalModelManager.instance;
  final _sourcePolicy = ModelDownloadSourcePolicy.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  RealtimeDictationPreferences _preferences =
      const RealtimeDictationPreferences();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_changed);
    _sourcePolicy.addListener(_changed);
    // Model files may have been replaced by an app upgrade or removed outside
    // this page. Always validate the on-disk runtime instead of showing a
    // possibly stale singleton snapshot.
    unawaited(_manager.initialize(force: true));
    unawaited(_sourcePolicy.load());
    unawaited(_loadDictationPreferences());
  }

  Future<void> _loadDictationPreferences() async {
    final preferences = await _dictationPreferences.load();
    if (mounted) setState(() => _preferences = preferences);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_changed);
    _sourcePolicy.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = _manager.models
        .where((model) => model.category == LocalModelCategory.language)
        .toList();
    final speech = _manager.models
        .where((model) => model.category == LocalModelCategory.speech)
        .toList();
    final vision = _manager.models
        .where((model) => model.category == LocalModelCategory.vision)
        .toList();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          context.l10n.localModelsPageTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const Key('discover-taobao-mnn-models'),
            tooltip: context.l10n.discoverMnnModels,
            onPressed: _openMnnCatalog,
            icon: const Icon(Icons.travel_explore_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            _ModelSummary(
              installedCount: _manager.installedCount,
              installedSizeBytes: _manager.installedSizeBytes,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 19,
                    color: AppColors.moss,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      context.l10n.modelPrivacyHint,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _DownloadSourceCard(
              preference: _sourcePolicy.preference,
              automaticPrefersMainland: _sourcePolicy.regionPrefersMainland,
              lastUsedSourceLabel: _sourcePolicy.lastUsedSourceLabel,
              onTap: _chooseDownloadSource,
            ),
            const SizedBox(height: 26),
            _sectionTitle(context.l10n.languageModels),
            const SizedBox(height: 6),
            Text(
              context.l10n.languageModelsDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < language.length; index++) ...[
              _ModelCard(
                definition: language[index],
                installation: _manager.installationOf(language[index].id),
                transfer: _manager.transferOf(language[index].id),
                emphasized: language[index].id == widget.focusModelId,
                selectedForAssistant:
                    language[index].id == _manager.selectedAssistantModelId,
                onDownload: () => _confirmDownload(language[index]),
                onImport: () => _manager.import(language[index].id),
                onCancel: () => _manager.cancel(language[index].id),
                onRemove: () => _confirmRemove(language[index]),
                onSelect: () => _selectForAssistant(language[index]),
                onDetails: () => _showDetails(language[index]),
              ),
              if (index != language.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 26),
            _sectionTitle(context.l10n.liveDictationSettings),
            const SizedBox(height: 12),
            _HotwordsCard(preferences: _preferences, onTap: _editHotwords),
            const SizedBox(height: 12),
            _TwoPassCard(
              enabled: _preferences.twoPassEnabled,
              onChanged: _setTwoPassEnabled,
            ),
            const SizedBox(height: 12),
            _NoiseSuppressionCard(
              enabled: _preferences.noiseSuppressionEnabled,
              modelInstalled: _manager
                  .installationOf(LocalModelManager.speechDenoiserId)
                  .installed,
              onChanged: _setNoiseSuppressionEnabled,
            ),
            const SizedBox(height: 26),
            _sectionTitle(context.l10n.speechModels),
            const SizedBox(height: 12),
            for (var index = 0; index < speech.length; index++) ...[
              _ModelCard(
                definition: speech[index],
                installation: _manager.installationOf(speech[index].id),
                transfer: _manager.transferOf(speech[index].id),
                emphasized: speech[index].id == widget.focusModelId,
                selectedForLiveDictation:
                    speech[index].id == _manager.selectedLiveDictationModelId,
                onDownload: () => _confirmDownload(speech[index]),
                onImport: () => _manager.import(speech[index].id),
                onCancel: () => _manager.cancel(speech[index].id),
                onRemove: () => _confirmRemove(speech[index]),
                onSelect: () => _selectForLiveDictation(speech[index]),
                onDetails: () => _showDetails(speech[index]),
              ),
              if (index != speech.length - 1) const SizedBox(height: 12),
            ],
            if (vision.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionTitle(context.l10n.visionModels),
              const SizedBox(height: 12),
              for (var index = 0; index < vision.length; index++) ...[
                _ModelCard(
                  definition: vision[index],
                  installation: _manager.installationOf(vision[index].id),
                  transfer: _manager.transferOf(vision[index].id),
                  onDownload: () => _confirmDownload(vision[index]),
                  onImport: () => _manager.import(vision[index].id),
                  onCancel: () => _manager.cancel(vision[index].id),
                  onRemove: () => _confirmRemove(vision[index]),
                  onSelect: () {},
                  onDetails: () => _showDetails(vision[index]),
                ),
                if (index != vision.length - 1) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _openMnnCatalog() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TaobaoMnnCatalogPage()),
    );
    if (added == true && mounted) {
      await _manager.initialize(force: true);
      if (mounted) {
        AppFeedback.success(context, context.l10n.modelAddedToManager);
      }
    }
  }

  Future<void> _chooseDownloadSource() async {
    final selected = await showModalBottomSheet<ModelDownloadSourcePreference>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.modelDownloadSource,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.downloadSourceSecurityDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 10),
            for (final preference in ModelDownloadSourcePreference.values)
              ListTile(
                key: Key('download-source-${preference.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(_downloadSourceIcon(preference)),
                title: Text(_downloadSourceTitle(context.l10n, preference)),
                subtitle: Text(
                  _downloadSourceDescription(context.l10n, preference),
                ),
                trailing: _sourcePolicy.preference == preference
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () => Navigator.pop(context, preference),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await _sourcePolicy.setPreference(selected);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.downloadSourceSaveFailed);
      }
    }
  }

  Future<void> _confirmDownload(LocalModelDefinition model) async {
    final installation = _manager.installationOf(model.id);
    final remaining = (model.downloadSizeBytes - installation.partialSizeBytes)
        .clamp(0, model.downloadSizeBytes);
    final l10n = context.l10n;
    final description = [
      l10n.modelDownloadDescription(
        localizedModelName(l10n, model),
        _formatBytes(remaining),
      ),
      if (model.recommendedMemoryBytes > 0)
        l10n.modelMemoryRecommendation(
          _formatMemory(model.recommendedMemoryBytes),
        ),
      if (model.task == LocalModelTask.textToSpeech)
        l10n.ttsStorageRecommendation,
    ].join('\n\n');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          installation.partialSizeBytes > 0
              ? context.l10n.continueModelDownloadQuestion
              : context.l10n.downloadModelQuestion,
        ),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.startDownload),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_manager.download(model.id));
  }

  Future<void> _confirmRemove(LocalModelDefinition model) async {
    final size = _manager.installationOf(model.id).installedSizeBytes;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.removeModelQuestion(
            localizedModelName(context.l10n, model),
          ),
        ),
        content: Text(context.l10n.removeModelDescription(_formatBytes(size))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.removeModel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.remove(model.id);
      await _loadDictationPreferences();
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _selectForLiveDictation(LocalModelDefinition model) async {
    if (model.task != LocalModelTask.liveDictation) return;
    try {
      await _manager.selectForLiveDictation(model.id);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _selectForAssistant(LocalModelDefinition model) async {
    if (model.category != LocalModelCategory.language) return;
    try {
      await _manager.selectForAssistant(model.id);
    } catch (error) {
      if (mounted) {
        AppFeedback.error(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    }
  }

  Future<void> _editHotwords() async {
    final result = await showModalBottomSheet<RealtimeDictationPreferences>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _HotwordsSheet(initial: _preferences, service: _dictationPreferences),
    );
    if (result == null || !mounted) return;
    setState(() => _preferences = result);
    AppFeedback.success(
      context,
      result.hotwordsEnabled
          ? context.l10n.hotwordsSaved(result.hotwords.length)
          : context.l10n.hotwordsDisabled,
    );
  }

  Future<void> _setTwoPassEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: enabled,
        noiseSuppressionEnabled: _preferences.noiseSuppressionEnabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.settingsSaveFailed);
      }
    }
  }

  Future<void> _setNoiseSuppressionEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: _preferences.twoPassEnabled,
        noiseSuppressionEnabled: enabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.settingsSaveFailed);
      }
    }
  }

  void _showDetails(LocalModelDefinition model) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizedModelName(context.l10n, model),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                localizedModelDescription(context.l10n, model),
                style: const TextStyle(height: 1.55),
              ),
              const SizedBox(height: 18),
              _DetailRow(
                context.l10n.purpose,
                localizedModelSummary(context.l10n, model),
              ),
              _DetailRow(context.l10n.engine, model.engine),
              if (model.languages.isNotEmpty)
                _DetailRow(
                  context.l10n.supportedLanguages,
                  localizedModelLanguages(context.l10n, model),
                ),
              if (model.version.isNotEmpty)
                _DetailRow(
                  context.l10n.version,
                  localizedModelVersion(context.l10n, model),
                ),
              if (model.recommendedMemoryBytes > 0)
                _DetailRow(
                  context.l10n.recommendedMemory,
                  context.l10n.memoryAndAbove(
                    _formatMemory(model.recommendedMemoryBytes),
                  ),
                ),
              if (model.source.isNotEmpty)
                _DetailRow(
                  context.l10n.source,
                  localizedModelSource(context.l10n, model),
                ),
              if (model.license.isNotEmpty)
                _DetailRow(context.l10n.license, model.license),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotwordsSheet extends StatefulWidget {
  final RealtimeDictationPreferences initial;
  final RealtimeDictationPreferencesService service;

  const _HotwordsSheet({required this.initial, required this.service});

  @override
  State<_HotwordsSheet> createState() => _HotwordsSheetState();
}

class _HotwordsSheetState extends State<_HotwordsSheet> {
  late final TextEditingController _controller;
  late double _score;
  String? _validationMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial.hotwords.join('\n'),
    );
    _score = widget.initial.hotwordsScore;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    try {
      final saved = await widget.service.save(
        hotwordsText: _controller.text,
        hotwordsScore: _score,
        twoPassEnabled: widget.initial.twoPassEnabled,
        noiseSuppressionEnabled: widget.initial.noiseSuppressionEnabled,
      );
      if (mounted) Navigator.pop(context, saved);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = error.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = context.l10n.saveFailedStorage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        MediaQuery.sizeOf(context).height - keyboardInset - 24;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.liveDictationHotwords,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.hotwordsDescription,
                  style: const TextStyle(color: AppColors.muted, height: 1.45),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('live-dictation-hotwords-field'),
                          controller: _controller,
                          contextMenuBuilder: buildAppEditableTextContextMenu,
                          minLines: 4,
                          maxLines: 8,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: context.l10n.hotwordsHint,
                            labelText: context.l10n.hotwordsList,
                            errorText: _validationMessage,
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: Text(context.l10n.boostStrength)),
                            Text(
                              _score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          key: const Key('live-dictation-hotwords-score'),
                          value: _score,
                          min: RealtimeDictationPreferencesService
                              .minHotwordsScore,
                          max: RealtimeDictationPreferencesService
                              .maxHotwordsScore,
                          divisions: 8,
                          label: _score.toStringAsFixed(1),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _score = value),
                        ),
                        Text(
                          context.l10n.hotwordsStrengthWarning,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(context.l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('save-live-dictation-hotwords'),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? context.l10n.saving : context.l10n.save,
                        ),
                      ),
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

class _TwoPassCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _TwoPassCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.auto_fix_high_rounded, color: AppColors.moss),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.finalRefinement,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.finalRefinementDescription,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('live-dictation-two-pass-switch'),
          value: enabled,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _NoiseSuppressionCard extends StatelessWidget {
  final bool enabled;
  final bool modelInstalled;
  final ValueChanged<bool> onChanged;

  const _NoiseSuppressionCard({
    required this.enabled,
    required this.modelInstalled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.noise_control_off_rounded,
            color: AppColors.moss,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.liveNoiseSuppression,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                modelInstalled
                    ? context.l10n.liveNoiseSuppressionDescription
                    : context.l10n.installDenoiserFirst,
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('live-dictation-noise-suppression-switch'),
          value: modelInstalled && enabled,
          onChanged: modelInstalled ? onChanged : null,
        ),
      ],
    ),
  );
}

class _HotwordsCard extends StatelessWidget {
  final RealtimeDictationPreferences preferences;
  final VoidCallback onTap;

  const _HotwordsCard({required this.preferences, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      key: const Key('live-dictation-hotwords-card'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.local_fire_department_outlined,
                color: AppColors.moss,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.hotwordBoost,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preferences.hotwordsEnabled
                        ? context.l10n.hotwordSummary(
                            preferences.hotwords.length,
                            preferences.hotwordsScore.toStringAsFixed(1),
                          )
                        : context.l10n.hotwordBoostDescription,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _DownloadSourceCard extends StatelessWidget {
  final ModelDownloadSourcePreference preference;
  final bool automaticPrefersMainland;
  final String? lastUsedSourceLabel;
  final VoidCallback onTap;

  const _DownloadSourceCard({
    required this.preference,
    required this.automaticPrefersMainland,
    required this.lastUsedSourceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effective = preference == ModelDownloadSourcePreference.automatic
        ? context.l10n.downloadSourceEffective(
            automaticPrefersMainland
                ? context.l10n.mainlandMirror
                : context.l10n.officialSource,
          )
        : _downloadSourceTitle(context.l10n, preference);
    final lastUsed = lastUsedSourceLabel;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('model-download-source-setting'),
        onTap: onTap,
        leading: const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.softBlue,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.cloud_download_outlined, color: AppColors.moss),
          ),
        ),
        title: Text(
          context.l10n.modelDownloadSource,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          lastUsed == null
              ? effective
              : '$effective\n${context.l10n.lastUsedSource(lastUsed)}',
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

String _downloadSourceTitle(
  AppLocalizations l10n,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic => l10n.downloadSourceAutomatic,
  ModelDownloadSourcePreference.officialFirst =>
    l10n.downloadSourceOfficialFirst,
  ModelDownloadSourcePreference.mainlandFirst =>
    l10n.downloadSourceMainlandFirst,
};

String _downloadSourceDescription(
  AppLocalizations l10n,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic =>
    l10n.downloadSourceAutomaticDescription,
  ModelDownloadSourcePreference.officialFirst =>
    l10n.downloadSourceOfficialDescription,
  ModelDownloadSourcePreference.mainlandFirst =>
    l10n.downloadSourceMainlandDescription,
};

IconData _downloadSourceIcon(ModelDownloadSourcePreference preference) =>
    switch (preference) {
      ModelDownloadSourcePreference.automatic => Icons.auto_mode_rounded,
      ModelDownloadSourcePreference.officialFirst => Icons.public_rounded,
      ModelDownloadSourcePreference.mainlandFirst => Icons.speed_rounded,
    };

String _localizedDownloadSourceLabel(AppLocalizations l10n, String label) =>
    switch (label) {
      '第三方国内镜像' => l10n.thirdPartyMainlandMirror,
      'GitHub 官方源' => l10n.githubOfficialSource,
      'ModelScope 魔搭' => l10n.modelScopeSource,
      _ => label,
    };

class _ModelSummary extends StatelessWidget {
  final int installedCount;
  final int installedSizeBytes;
  const _ModelSummary({
    required this.installedCount,
    required this.installedSizeBytes,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.memory_rounded, color: AppColors.moss),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.installedModelCount(installedCount),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                context.l10n.optionalModelsUsage(
                  _formatBytes(installedSizeBytes),
                ),
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  final LocalModelDefinition definition;
  final LocalModelInstallation installation;
  final ModelTransferState? transfer;
  final bool emphasized;
  final bool selectedForLiveDictation;
  final bool selectedForAssistant;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final VoidCallback onSelect;
  final VoidCallback onDetails;
  const _ModelCard({
    required this.definition,
    required this.installation,
    required this.transfer,
    this.emphasized = false,
    this.selectedForLiveDictation = false,
    this.selectedForAssistant = false,
    required this.onDownload,
    required this.onImport,
    required this.onCancel,
    required this.onRemove,
    required this.onSelect,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final running = transfer?.isRunning == true;
    final icon = switch (definition.task) {
      LocalModelTask.audioTranscription => Icons.graphic_eq_rounded,
      LocalModelTask.liveDictation => Icons.mic_rounded,
      LocalModelTask.voiceActivityDetection => Icons.multiline_chart_rounded,
      LocalModelTask.speechEnhancement => Icons.noise_control_off_rounded,
      LocalModelTask.speakerDiarization => Icons.groups_2_outlined,
      LocalModelTask.textToSpeech => Icons.record_voice_over_rounded,
      LocalModelTask.textGeneration => Icons.auto_awesome_rounded,
      LocalModelTask.textRecognition => Icons.document_scanner_rounded,
      LocalModelTask.imageUnderstanding => Icons.image_search_rounded,
    };
    return Container(
      key: Key('model-card-${definition.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: emphasized ? AppColors.moss : AppColors.line,
          width: emphasized ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.moss),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizedModelName(context.l10n, definition),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (definition.recommended ||
                        (selectedForLiveDictation &&
                            definition.task == LocalModelTask.liveDictation) ||
                        (selectedForAssistant &&
                            installation.installed &&
                            definition.category ==
                                LocalModelCategory.language)) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          if (definition.recommended)
                            _StatusBadge(label: context.l10n.recommended),
                          if (selectedForLiveDictation &&
                              definition.task == LocalModelTask.liveDictation)
                            _StatusBadge(
                              label: context.l10n.currentDictation,
                              installed: installation.installed,
                            ),
                          if (selectedForAssistant &&
                              installation.installed &&
                              definition.category ==
                                  LocalModelCategory.language)
                            _StatusBadge(
                              label: context.l10n.currentAssistant,
                              installed: true,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      localizedModelSummary(context.l10n, definition),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.modelDetails,
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline_rounded, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _MetaChip(label: definition.engine),
              if (definition.downloadSizeBytes > 0)
                _MetaChip(label: _formatBytes(definition.downloadSizeBytes)),
              if (definition.recommendedMemoryBytes > 0)
                _MetaChip(
                  label: context.l10n.memoryBadge(
                    _formatMemory(definition.recommendedMemoryBytes),
                  ),
                ),
              if (definition.languages.isNotEmpty)
                _MetaChip(
                  label: localizedModelLanguages(
                    context.l10n,
                    definition,
                  ).split(RegExp(r', |、')).take(2).join(' / '),
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: transfer!.progress <= 0 ? null : transfer!.progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _transferDescription(context, transfer!),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (transfer!.status == ModelTransferStatus.verifying ||
                    transfer!.status == ModelTransferStatus.canceling ||
                    !transfer!.cancelable)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      context.l10n.pleaseWait,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed: onCancel,
                    child: Text(context.l10n.cancel),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 15),
            _actions(context),
          ],
          if (transfer?.status == ModelTransferStatus.failed) ...[
            const SizedBox(height: 9),
            Text(
              transfer?.errorMessage ?? context.l10n.modelDownloadFailed,
              style: const TextStyle(color: AppColors.coral, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    if (definition.availability == LocalModelAvailability.builtIn) {
      return Align(
        alignment: Alignment.centerRight,
        child: _StatusBadge(
          label: context.l10n.bundledWithApp,
          installed: true,
        ),
      );
    }
    if (definition.availability == LocalModelAvailability.planned) {
      return Align(
        alignment: Alignment.centerRight,
        child: _StatusBadge(label: context.l10n.comingSoon),
      );
    }
    if (installation.installed) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(label: context.l10n.installed, installed: true),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (definition.task == LocalModelTask.liveDictation &&
                    !selectedForLiveDictation)
                  TextButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(context.l10n.useForDictation),
                  ),
                if (definition.category == LocalModelCategory.language &&
                    !selectedForAssistant)
                  TextButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(context.l10n.useForAssistant),
                  ),
                TextButton.icon(
                  key: Key('model-remove-${definition.id}'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  label: Text(context.l10n.remove),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final canContinue =
        installation.partialSizeBytes > 0 ||
        transfer?.status == ModelTransferStatus.canceled ||
        transfer?.status == ModelTransferStatus.failed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final importButton = TextButton.icon(
          key: Key('model-import-${definition.id}'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onImport,
          icon: const Icon(Icons.folder_open_rounded, size: 19),
          label: Text(context.l10n.importFromFile),
        );
        final downloadButton = FilledButton.icon(
          key: Key('model-download-${definition.id}'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded, size: 19),
          label: Text(
            canContinue ? context.l10n.continueDownload : context.l10n.download,
          ),
        );
        if (constraints.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [importButton, const SizedBox(height: 8), downloadButton],
          );
        }
        return Row(
          children: [
            Expanded(child: importButton),
            const SizedBox(width: 10),
            Expanded(child: downloadButton),
          ],
        );
      },
    );
  }

  String _transferDescription(BuildContext context, ModelTransferState state) {
    if (state.status == ModelTransferStatus.canceling) {
      return context.l10n.cancelingDownload;
    }
    if (state.status == ModelTransferStatus.connecting) {
      final source = state.sourceLabel.isEmpty
          ? ''
          : ' · ${_localizedDownloadSourceLabel(context.l10n, state.sourceLabel)}';
      return context.l10n.connectingDownloadSource(source);
    }
    if (state.status == ModelTransferStatus.verifying) {
      return context.l10n.downloadedInstalling(
        _formatBytes(state.transferredBytes),
      );
    }
    if (state.status == ModelTransferStatus.waitingToInstall) {
      return context.l10n.downloadedWaitingInstall(
        _formatBytes(state.transferredBytes),
      );
    }
    final verb = state.status == ModelTransferStatus.importing
        ? context.l10n.importedVerb
        : context.l10n.downloadedVerb;
    final speed = state.bytesPerSecond <= 0
        ? context.l10n.waitingFirstPacket
        : '${_formatBytes(state.bytesPerSecond.round())}/s';
    final source = state.sourceLabel.isEmpty
        ? ''
        : ' · ${_localizedDownloadSourceLabel(context.l10n, state.sourceLabel)}';
    return '$verb ${_formatBytes(state.transferredBytes)} / '
        '${_formatBytes(state.totalBytes)}$source · $speed';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool installed;
  const _StatusBadge({required this.label, this.installed = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: installed ? AppColors.softGreen : AppColors.softBlue,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: installed ? AppColors.moss : AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.line),
    ),
    child: Text(
      label,
      style: const TextStyle(color: AppColors.muted, fontSize: 11),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _formatBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : bytes < 1073741824
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1073741824).toStringAsFixed(1)} GB';

String _formatMemory(int bytes) => '${(bytes / 1073741824).round()} GB';
