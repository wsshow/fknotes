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
import '../widgets/empty_state.dart';
import 'taobao_mnn_catalog_page.dart';

class ModelManagementPage extends StatefulWidget {
  final String? focusModelId;
  final LocalModelCategory? category;
  final bool showDictationSettings;
  final bool showDownloadSettings;
  final bool showTransferTasks;

  const ModelManagementPage({
    super.key,
    this.focusModelId,
    this.category,
    this.showDictationSettings = false,
    this.showDownloadSettings = false,
    this.showTransferTasks = false,
  });

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  final _manager = LocalModelManager.instance;
  final _sourcePolicy = ModelDownloadSourcePolicy.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  RealtimeDictationPreferences _preferences =
      const RealtimeDictationPreferences();
  bool _showInstalledModels = true;

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
    if (widget.showDictationSettings) return _buildDictationSettings(context);
    if (widget.showDownloadSettings) return _buildDownloadSettings(context);
    if (widget.showTransferTasks) return _buildTransferTasks(context);
    final category = widget.category ?? _focusedCategory;
    if (category != null) return _buildCategory(context, category);
    return _buildOverview(context);
  }

  LocalModelCategory? get _focusedCategory {
    final id = widget.focusModelId;
    if (id == null) return null;
    try {
      return _manager.modelOf(id).category;
    } catch (_) {
      return null;
    }
  }

  Widget _buildOverview(BuildContext context) {
    final active = _manager.activeModels(_preferences);
    final transferModels = _sortedTransferModels(_manager.models);
    final activeSize = active.fold<int>(
      0,
      (total, item) => total + item.installation.installedSizeBytes,
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          context.l10n.localModelsPageTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            _ModelSummary(
              installedCount: active.length,
              installedSizeBytes: activeSize,
              activeOnly: true,
            ),
            if (transferModels.isNotEmpty) ...[
              const SizedBox(height: 14),
              _ModelCategoryLink(
                key: const Key('model-transfer-tasks-link'),
                icon: Icons.downloading_rounded,
                title: context.l10n.modelTransfers,
                subtitle: _transferTaskSummary(transferModels),
                onTap: _openTransferTasks,
              ),
            ],
            const SizedBox(height: 26),
            _sectionTitle(context.l10n.modelsInUse),
            const SizedBox(height: 12),
            if (active.isEmpty)
              EmptyState(
                icon: Icons.memory_outlined,
                message: context.l10n.noModelsInUse,
              )
            else
              for (var index = 0; index < active.length; index++) ...[
                _ActiveModelCard(
                  model: active[index],
                  onTap: () => _openCategory(
                    active[index].definition.category,
                    focusModelId: active[index].definition.id,
                  ),
                  onDetails: () => _showDetails(active[index].definition),
                ),
                if (index != active.length - 1) const SizedBox(height: 12),
              ],
            const SizedBox(height: 26),
            _sectionTitle(context.l10n.modelConfiguration),
            const SizedBox(height: 12),
            _ModelCategoryLink(
              icon: Icons.auto_awesome_rounded,
              title: context.l10n.languageModels,
              subtitle: _categorySubtitle(LocalModelCategory.language),
              onTap: () => _openCategory(LocalModelCategory.language),
            ),
            const SizedBox(height: 10),
            _ModelCategoryLink(
              icon: Icons.graphic_eq_rounded,
              title: context.l10n.speechModels,
              subtitle: context.l10n.speechModelsDescription,
              onTap: () => _openCategory(LocalModelCategory.speech),
            ),
            const SizedBox(height: 10),
            _ModelCategoryLink(
              icon: Icons.image_search_rounded,
              title: context.l10n.visionModels,
              subtitle: _categorySubtitle(LocalModelCategory.vision),
              onTap: () => _openCategory(LocalModelCategory.vision),
            ),
            const SizedBox(height: 10),
            _ModelCategoryLink(
              icon: Icons.cloud_download_outlined,
              title: context.l10n.modelDownloadsAndStorage,
              subtitle: context.l10n.modelDownloadsAndStorageDescription,
              onTap: _openDownloadSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategory(BuildContext context, LocalModelCategory category) {
    final models = _manager.models
        .where((model) => model.category == category)
        .toList();
    final focusedId = widget.focusModelId;
    final focusInstalled =
        focusedId != null && _manager.installationOf(focusedId).installed;
    final showInstalled = focusedId == null
        ? _showInstalledModels
        : focusInstalled;
    final transferModels = _sortedTransferModels(models);
    final transferModelIds = transferModels.map((model) => model.id).toSet();
    final visible = models.where((model) {
      final installed =
          model.availability == LocalModelAvailability.builtIn ||
          _manager.installationOf(model.id).installed;
      return !transferModelIds.contains(model.id) &&
          (showInstalled ? installed : !installed);
    }).toList();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_categoryTitle(category)),
        actions: category == LocalModelCategory.language
            ? [
                IconButton(
                  key: const Key('discover-taobao-mnn-models'),
                  tooltip: context.l10n.discoverMnnModels,
                  onPressed: _openMnnCatalog,
                  icon: const Icon(Icons.travel_explore_rounded),
                ),
                const SizedBox(width: 6),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              _categoryDescription(category),
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (category == LocalModelCategory.speech) ...[
              const SizedBox(height: 16),
              _ModelCategoryLink(
                icon: Icons.mic_rounded,
                title: context.l10n.liveDictationSettings,
                subtitle: context.l10n.liveDictationSettingsDescription,
                onTap: _openDictationSettings,
              ),
            ],
            if (transferModels.isNotEmpty) ...[
              const SizedBox(height: 22),
              _TransferSectionHeader(
                count: transferModels.length,
                subtitle: _transferTaskSummary(transferModels),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < transferModels.length; index++) ...[
                _modelCard(
                  transferModels[index],
                  emphasized: transferModels[index].id == focusedId,
                ),
                if (index != transferModels.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              key: const Key('model-installation-filter'),
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(context.l10n.installedModels),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(context.l10n.availableModels),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
              selected: {showInstalled},
              onSelectionChanged: focusedId != null
                  ? null
                  : (value) =>
                        setState(() => _showInstalledModels = value.first),
            ),
            const SizedBox(height: 18),
            if (transferModels.isNotEmpty) ...[
              _sectionTitle(context.l10n.otherModels),
              const SizedBox(height: 12),
            ],
            if (visible.isEmpty)
              EmptyState(
                icon: showInstalled
                    ? Icons.inventory_2_outlined
                    : Icons.manage_search_rounded,
                message: showInstalled
                    ? context.l10n.noInstalledModelsInCategory
                    : context.l10n.noAvailableModelsInCategory,
              )
            else
              for (var index = 0; index < visible.length; index++) ...[
                _modelCard(
                  visible[index],
                  emphasized: visible[index].id == focusedId,
                ),
                if (index != visible.length - 1) const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransferTasks(BuildContext context) {
    final models = _sortedTransferModels(_manager.models);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.modelTransfers)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              context.l10n.modelTransfersDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (models.isEmpty)
              EmptyState(
                icon: Icons.download_done_rounded,
                message: context.l10n.noModelTransfers,
              )
            else
              for (var index = 0; index < models.length; index++) ...[
                _modelCard(models[index]),
                if (index != models.length - 1) const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _modelCard(LocalModelDefinition model, {bool emphasized = false}) =>
      _ModelCard(
        definition: model,
        installation: _manager.installationOf(model.id),
        transfer: _manager.transferOf(model.id),
        emphasized: emphasized,
        selectedForLiveDictation:
            model.id == _manager.selectedLiveDictationModelId,
        selectedForAssistant: model.id == _manager.selectedAssistantModelId,
        onDownload: () => _confirmDownload(model),
        onImport: () => _manager.import(model.id),
        onCancel: () => _manager.cancel(model.id),
        onDiscardPartial: () => _confirmDiscardPartial(model),
        onRemove: () => _confirmRemove(model),
        onSelect: () => model.category == LocalModelCategory.language
            ? _selectForAssistant(model)
            : _selectForLiveDictation(model),
        onDetails: () => _showDetails(model),
      );

  List<LocalModelDefinition> _sortedTransferModels(
    Iterable<LocalModelDefinition> source,
  ) {
    final result = source.where(_isTransferModel).toList();
    result.sort((left, right) {
      final rank = _transferRank(left).compareTo(_transferRank(right));
      if (rank != 0) return rank;
      return localizedModelName(
        context.l10n,
        left,
      ).compareTo(localizedModelName(context.l10n, right));
    });
    return result;
  }

  bool _isTransferModel(LocalModelDefinition model) {
    final installation = _manager.installationOf(model.id);
    if (installation.installed) return false;
    final transfer = _manager.transferOf(model.id);
    return installation.partialSizeBytes > 0 ||
        transfer?.isRunning == true ||
        transfer?.status == ModelTransferStatus.failed ||
        transfer?.status == ModelTransferStatus.canceled;
  }

  int _transferRank(LocalModelDefinition model) {
    final status = _manager.transferOf(model.id)?.status;
    return switch (status) {
      ModelTransferStatus.downloading || ModelTransferStatus.importing => 0,
      ModelTransferStatus.connecting => 1,
      ModelTransferStatus.waitingToInstall ||
      ModelTransferStatus.verifying ||
      ModelTransferStatus.canceling => 2,
      ModelTransferStatus.failed => 3,
      ModelTransferStatus.canceled => 4,
      _ => 5,
    };
  }

  String _transferTaskSummary(List<LocalModelDefinition> models) {
    final active = models.where((model) {
      return _manager.transferOf(model.id)?.isRunning == true;
    }).length;
    return context.l10n.modelTransferSummary(active, models.length - active);
  }

  Widget _buildDictationSettings(BuildContext context) {
    final selected = _manager.modelOf(_manager.selectedLiveDictationModelId);
    final installation = _manager.installationOf(selected.id);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.liveDictationSettings)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            if (installation.installed) ...[
              _ActiveModelCard(
                model: ActiveLocalModel(
                  definition: selected,
                  installation: installation,
                  usages: const {LocalModelUsage.liveDictation},
                ),
                onTap: () => _openCategory(
                  LocalModelCategory.speech,
                  focusModelId: selected.id,
                ),
                onDetails: () => _showDetails(selected),
              ),
              const SizedBox(height: 18),
            ],
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
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSettings(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(title: Text(context.l10n.modelDownloadsAndStorage)),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          _ModelSummary(
            installedCount: _manager.installedCount,
            installedSizeBytes: _manager.installedSizeBytes,
          ),
          const SizedBox(height: 14),
          _DownloadSourceCard(
            preference: _sourcePolicy.preference,
            automaticPrefersMainland: _sourcePolicy.regionPrefersMainland,
            lastUsedSourceLabel: _sourcePolicy.lastUsedSourceLabel,
            onTap: _chooseDownloadSource,
          ),
          const SizedBox(height: 14),
          _PrivacyNotice(message: context.l10n.modelPrivacyHint),
        ],
      ),
    ),
  );

  String _categoryTitle(LocalModelCategory category) => switch (category) {
    LocalModelCategory.language => context.l10n.languageModels,
    LocalModelCategory.speech => context.l10n.speechModels,
    LocalModelCategory.vision => context.l10n.visionModels,
  };

  String _categoryDescription(LocalModelCategory category) =>
      switch (category) {
        LocalModelCategory.language => context.l10n.languageModelsDescription,
        LocalModelCategory.speech => context.l10n.speechModelsDescription,
        LocalModelCategory.vision => context.l10n.visionModelsDescription,
      };

  String _categorySubtitle(LocalModelCategory category) {
    final installed = _manager.models.where((model) {
      return model.category == category &&
          (model.availability == LocalModelAvailability.builtIn ||
              _manager.installationOf(model.id).installed);
    }).length;
    return context.l10n.installedModelsCount(installed);
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _openCategory(
    LocalModelCategory category, {
    String? focusModelId,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ModelManagementPage(category: category, focusModelId: focusModelId),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

  Future<void> _openDictationSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showDictationSettings: true),
      ),
    );
    if (mounted) {
      await _loadDictationPreferences();
      await _manager.initialize(force: true);
    }
  }

  Future<void> _openDownloadSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showDownloadSettings: true),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

  Future<void> _openTransferTasks() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const ModelManagementPage(showTransferTasks: true),
      ),
    );
    if (mounted) await _manager.initialize(force: true);
  }

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

  Future<void> _confirmDiscardPartial(LocalModelDefinition model) async {
    final size = _manager.installationOf(model.id).partialSizeBytes;
    if (size <= 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.discardPartialDownloadQuestion(
            localizedModelName(context.l10n, model),
          ),
        ),
        content: Text(
          context.l10n.discardPartialDownloadDescription(_formatBytes(size)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.discardPartialDownload),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.remove(model.id);
    } catch (_) {
      if (mounted) {
        AppFeedback.error(context, context.l10n.discardPartialDownloadFailed);
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

class _PrivacyNotice extends StatelessWidget {
  final String message;

  const _PrivacyNotice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 19, color: AppColors.moss),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.muted, height: 1.55),
          ),
        ),
      ],
    ),
  );
}

class _ModelCategoryLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModelCategoryLink({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
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
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
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

class _TransferSectionHeader extends StatelessWidget {
  final int count;
  final String subtitle;

  const _TransferSectionHeader({required this.count, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.softGreen,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.downloading_rounded,
          size: 20,
          color: AppColors.moss,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.modelTransferSectionCount(count),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ActiveModelCard extends StatelessWidget {
  final ActiveLocalModel model;
  final VoidCallback onTap;
  final VoidCallback? onDetails;

  const _ActiveModelCard({
    required this.model,
    required this.onTap,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final definition = model.definition;
    return Material(
      key: Key('active-model-${definition.id}'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    child: Icon(
                      _modelIcon(definition.task),
                      color: AppColors.moss,
                    ),
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
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final usage in model.usages)
                              _StatusBadge(
                                label: _usageLabel(context.l10n, usage),
                                installed: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onDetails != null)
                    IconButton(
                      tooltip: context.l10n.modelDetails,
                      onPressed: onDetails,
                      icon: const Icon(Icons.info_outline_rounded, size: 21),
                    ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _MetaChip(label: definition.engine),
                  if (model.installation.installedSizeBytes > 0)
                    _MetaChip(
                      label: _formatBytes(
                        model.installation.installedSizeBytes,
                      ),
                    ),
                  if (definition.availability == LocalModelAvailability.builtIn)
                    _MetaChip(label: context.l10n.bundledWithApp),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _usageLabel(AppLocalizations l10n, LocalModelUsage usage) =>
    switch (usage) {
      LocalModelUsage.assistant => l10n.localAssistantUsage,
      LocalModelUsage.liveDictation => l10n.liveDictationUsage,
      LocalModelUsage.audioTranscription => l10n.audioTranscriptionUsage,
      LocalModelUsage.voiceActivityDetection => l10n.voiceActivityUsage,
      LocalModelUsage.speechEnhancement => l10n.speechEnhancementUsage,
      LocalModelUsage.textRecognition => l10n.textRecognitionUsage,
    };

IconData _modelIcon(LocalModelTask task) => switch (task) {
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
  final bool activeOnly;
  const _ModelSummary({
    required this.installedCount,
    required this.installedSizeBytes,
    this.activeOnly = false,
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
                activeOnly
                    ? context.l10n.activeModelCount(installedCount)
                    : context.l10n.installedModelCount(installedCount),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                activeOnly
                    ? context.l10n.activeModelsUsage(
                        _formatBytes(installedSizeBytes),
                      )
                    : context.l10n.optionalModelsUsage(
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
  final VoidCallback onDiscardPartial;
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
    required this.onDiscardPartial,
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
                  definition.category == LocalModelCategory.language)
                _StatusBadge(
                  label: context.l10n.currentAssistant,
                  installed: true,
                ),
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
            _transferStatus(context, transfer!),
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

  Widget _transferStatus(BuildContext context, ModelTransferState state) {
    if (state.status == ModelTransferStatus.importing &&
        state.totalBytes <= 0) {
      return Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.preparingLocalModelImport,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          _transferAction(context, state),
        ],
      );
    }
    if (state.status != ModelTransferStatus.downloading &&
        state.status != ModelTransferStatus.importing) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _transferDescription(context, state),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          _transferAction(context, state),
        ],
      );
    }
    const numberStyle = TextStyle(
      color: AppColors.muted,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final amount =
        '${_formatBytes(state.transferredBytes)} / '
        '${_formatBytes(state.totalBytes)}';
    final eta = state.estimatedRemaining;
    final etaText = context.l10n.estimatedRemainingCompact(
      eta == null ? '--:--:--' : _formatDurationClock(eta),
    );
    final source = state.status == ModelTransferStatus.importing
        ? context.l10n.localModelImportTransfer
        : state.sourceLabel.isEmpty
        ? context.l10n.modelDownloadTransfer
        : _localizedDownloadSourceLabel(context.l10n, state.sourceLabel);
    final speed = state.bytesPerSecond <= 0
        ? context.l10n.speedTesting
        : '${_formatBytes(state.bytesPerSecond.round())}/s';
    return Semantics(
      label: '$amount, $source, $speed, $etaText',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numberStyle,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 104,
                  child: Text(
                    etaText,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.clip,
                    style: numberStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Text(
                        ' · ',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      Text(speed, maxLines: 1, style: numberStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _transferAction(context, state),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferAction(BuildContext context, ModelTransferState state) {
    if (state.status == ModelTransferStatus.verifying ||
        state.status == ModelTransferStatus.canceling ||
        !state.cancelable) {
      return SizedBox(
        width: 64,
        child: Center(
          child: Text(
            context.l10n.pleaseWait,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      );
    }
    return SizedBox(
      width: 64,
      child: TextButton(
        key: Key('model-pause-${definition.id}'),
        onPressed: onCancel,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(64, 36),
        ),
        child: Text(context.l10n.pauseDownload),
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
    final hasPartial = installation.partialSizeBytes > 0;
    final failed = transfer?.status == ModelTransferStatus.failed;
    final canContinue =
        hasPartial || transfer?.status == ModelTransferStatus.canceled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final importButton = TextButton.icon(
          key: Key('model-import-${definition.id}'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: onImport,
          icon: const Icon(Icons.folder_open_rounded, size: 19),
          label: Text(context.l10n.importFromFile),
        );
        final buttonKey = Key('model-download-${definition.id}');
        final Widget downloadButton;
        if (failed) {
          downloadButton = OutlinedButton.icon(
            key: buttonKey,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(112, 48),
              foregroundColor: AppColors.coral,
              side: const BorderSide(color: AppColors.coral),
            ),
            onPressed: onDownload,
            icon: const Icon(Icons.refresh_rounded, size: 19),
            label: Text(context.l10n.retry),
          );
        } else if (canContinue) {
          downloadButton = FilledButton.icon(
            key: buttonKey,
            style: FilledButton.styleFrom(minimumSize: const Size(112, 48)),
            onPressed: onDownload,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(context.l10n.continueDownload),
          );
        } else {
          downloadButton = FilledButton.tonalIcon(
            key: buttonKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size(112, 48),
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.moss,
            ),
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 19),
            label: Text(context.l10n.download),
          );
        }
        final actionRow = constraints.maxWidth < 280
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: importButton),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: downloadButton,
                  ),
                ],
              )
            : Row(
                children: [
                  importButton,
                  const Spacer(),
                  const SizedBox(width: 8),
                  downloadButton,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPartial) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.downloadedResumable(
                        _formatBytes(installation.partialSizeBytes),
                      ),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  PopupMenuButton<_PartialDownloadAction>(
                    key: Key('model-partial-menu-${definition.id}'),
                    tooltip: context.l10n.moreActions,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    onSelected: (_) => onDiscardPartial(),
                    itemBuilder: (context) => [
                      PopupMenuItem<_PartialDownloadAction>(
                        value: _PartialDownloadAction.discard,
                        child: Row(
                          children: [
                            const Icon(Icons.delete_sweep_outlined, size: 19),
                            const SizedBox(width: 10),
                            Text(context.l10n.discardPartialDownload),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            actionRow,
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
    return '';
  }
}

enum _PartialDownloadAction { discard }

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

String _formatDurationClock(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
