import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../app.dart';
import '../debug/app_diagnostics.dart';
import '../l10n/l10n.dart';
import '../models/litert_model.dart';
import '../models/taobao_mnn_model.dart';
import '../services/language_model_service.dart';
import '../services/litert_catalog_service.dart';
import '../services/local_model_manager.dart';
import '../services/model_catalog_http_client.dart';
import '../services/model_download_source_policy.dart';
import '../services/taobao_mnn_catalog_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/editor_context_menu.dart';

class TaobaoMnnCatalogPage extends StatefulWidget {
  final TaobaoMnnCatalogService? service;
  final LiteRtCatalogService? liteRtService;
  final Set<String>? curatedRepositories;
  final Future<void> Function(TaobaoMnnModelSpec model)? onInstall;
  final Future<void> Function(LiteRtModelSpec model)? onInstallLiteRt;
  final ModelDownloadSourcePolicy? sourcePolicy;
  final bool? includeLiteRt;

  const TaobaoMnnCatalogPage({
    super.key,
    this.service,
    this.liteRtService,
    this.curatedRepositories,
    this.onInstall,
    this.onInstallLiteRt,
    this.sourcePolicy,
    this.includeLiteRt,
  });

  @override
  State<TaobaoMnnCatalogPage> createState() => _TaobaoMnnCatalogPageState();
}

class _TaobaoMnnCatalogPageState extends State<TaobaoMnnCatalogPage> {
  late final TaobaoMnnCatalogService _service;
  late final LiteRtCatalogService _liteRtService;
  late final bool _includeLiteRt;
  late final Set<String> _curatedRepositories;
  late final ModelDownloadSourcePolicy _sourcePolicy;
  final _search = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TaobaoMnnCatalogService.instance;
    _liteRtService = widget.liteRtService ?? LiteRtCatalogService.instance;
    _includeLiteRt = widget.includeLiteRt ?? widget.service == null;
    _sourcePolicy = widget.sourcePolicy ?? ModelDownloadSourcePolicy.instance;
    _curatedRepositories =
        widget.curatedRepositories ??
        LanguageModelService.instance.curatedRepositories;
    _search.addListener(_changed);
    _sourcePolicy.addListener(_changed);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_changed)
      ..dispose();
    _sourcePolicy.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await Future.wait([
      _sourcePolicy.load(),
      _service.loadCache(),
      if (_includeLiteRt) _liteRtService.loadCache(),
    ]);
    if (!mounted) return;
    setState(() => _loading = false);
    if (_service.entries.isEmpty &&
        (!_includeLiteRt || _liteRtService.entries.isEmpty)) {
      await _sync();
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final errors = await Future.wait([
        _captureSync(_service.sync),
        if (_includeLiteRt) _captureSync(_liteRtService.sync),
      ]);
      _error = errors.whereType<Object>().firstOrNull;
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<Object?> _captureSync(Future<Object?> Function() sync) async {
    try {
      await sync();
      return null;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.modelManagement,
          'model_catalog_refresh_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return error;
    }
  }

  Future<void> _chooseNetworkSource() async {
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
                contentPadding: EdgeInsets.zero,
                leading: Icon(_sourceIcon(preference)),
                title: Text(_sourceTitle(context, preference)),
                subtitle: Text(_sourceDescription(context, preference)),
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
    await _sourcePolicy.setPreference(selected);
    if (mounted) unawaited(_sync());
  }

  List<_CatalogEntryView> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    final entries = <_CatalogEntryView>[
      ..._service.entries.map(_CatalogEntryView.mnn),
      if (_includeLiteRt)
        ..._liteRtService.entries.map(_CatalogEntryView.liteRt),
    ];
    return entries.where((entry) {
      if (_curatedRepositories.contains(entry.repository.toLowerCase())) {
        return false;
      }
      return query.isEmpty ||
          entry.name.toLowerCase().contains(query) ||
          entry.collection.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _open(_CatalogEntryView entry) async {
    final installed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => entry.mnnEntry != null
            ? _TaobaoMnnModelDetailPage(
                entry: entry.mnnEntry!,
                service: _service,
                onInstall: widget.onInstall ?? _install,
              )
            : _LiteRtModelDetailPage(
                entry: entry.liteRtEntry!,
                service: _liteRtService,
                onInstall: widget.onInstallLiteRt ?? _installLiteRt,
              ),
      ),
    );
    if (installed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _install(TaobaoMnnModelSpec model) async {
    final manager = LocalModelManager.instance;
    await manager.registerRemoteModel(model);
  }

  Future<void> _installLiteRt(LiteRtModelSpec model) async {
    final manager = LocalModelManager.instance;
    await manager.registerRemoteLiteRtModel(model);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    final errorPresentation = _error == null
        ? null
        : _catalogErrorPresentation(context, _error!);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.discoverMnnModels),
        actions: [
          IconButton(
            tooltip: context.l10n.refreshCatalog,
            onPressed: _syncing ? null : _sync,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                  children: [
                    Text(
                      context.l10n.discoverMnnModelsDescription,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('taobao-mnn-search'),
                      controller: _search,
                      contextMenuBuilder: buildAppEditableTextContextMenu,
                      decoration: InputDecoration(
                        hintText: context.l10n.searchMnnModels,
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    if (_syncing) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 7),
                      Text(
                        context.l10n.syncingModelCatalog,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _CatalogNotice(
                        message: errorPresentation!.title,
                        secondary: [
                          errorPresentation.description,
                          if (_service.entries.isNotEmpty ||
                              (_includeLiteRt &&
                                  _liteRtService.entries.isNotEmpty))
                            context.l10n.cachedCatalogInUse,
                        ].join('\n'),
                        error: true,
                        actionLabel: context.l10n.retry,
                        onAction: _sync,
                        secondaryActionLabel:
                            context.l10n.modelNetworkSourceSettings,
                        onSecondaryAction: _chooseNetworkSource,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _CatalogNotice(
                      message: context.l10n.recommendedModelsAlreadyListed,
                    ),
                    const SizedBox(height: 18),
                    if (entries.isEmpty && !_syncing)
                      EmptyState(
                        icon: Icons.manage_search_rounded,
                        message: context.l10n.noMnnModelsFound,
                      )
                    else
                      for (final entry in entries) ...[
                        _CatalogModelCard(
                          entry: entry,
                          onTap: () => _open(entry),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _CatalogEntryView {
  final TaobaoMnnCatalogEntry? mnnEntry;
  final LiteRtCatalogEntry? liteRtEntry;

  const _CatalogEntryView.mnn(TaobaoMnnCatalogEntry entry)
    : mnnEntry = entry,
      liteRtEntry = null;

  const _CatalogEntryView.liteRt(LiteRtCatalogEntry entry)
    : mnnEntry = null,
      liteRtEntry = entry;

  String get repository => mnnEntry?.repository ?? liteRtEntry!.repository;
  String get name => mnnEntry?.name ?? liteRtEntry!.name;
  String get collection => mnnEntry?.collection ?? liteRtEntry!.collection;
  int get downloads => mnnEntry?.downloads ?? liteRtEntry!.downloads;
  String get engineLabel => mnnEntry != null ? 'MNN' : 'LiteRT-LM';
}

class _CatalogModelCard extends StatelessWidget {
  final _CatalogEntryView entry;
  final VoidCallback onTap;

  const _CatalogModelCard({required this.entry, required this.onTap});

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
            const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.memory_rounded, color: AppColors.moss),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.collection,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    entry.engineLabel,
                    style: const TextStyle(
                      color: AppColors.moss,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.downloads > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.downloadCount(entry.downloads),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
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

class _TaobaoMnnModelDetailPage extends StatefulWidget {
  final TaobaoMnnCatalogEntry entry;
  final TaobaoMnnCatalogService service;
  final Future<void> Function(TaobaoMnnModelSpec model) onInstall;

  const _TaobaoMnnModelDetailPage({
    required this.entry,
    required this.service,
    required this.onInstall,
  });

  @override
  State<_TaobaoMnnModelDetailPage> createState() =>
      _TaobaoMnnModelDetailPageState();
}

class _TaobaoMnnModelDetailPageState extends State<_TaobaoMnnModelDetailPage> {
  TaobaoMnnModelSpec? _model;
  Object? _error;
  bool _checking = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _model = widget.service.cachedSpec(widget.entry.repository);
  }

  Future<void> _inspect() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final model = await widget.service.inspect(widget.entry, force: true);
      if (mounted) setState(() => _model = model);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.modelManagement,
          'mnn_model_package_verification_failed',
          data: {'repository': widget.entry.repository},
          error: error,
          stackTrace: stackTrace,
          traceId: widget.entry.repository,
        );
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final model = _model;
    if (model == null || _installing) return;
    setState(() => _installing = true);
    try {
      await widget.onInstall(model);
      if (mounted) Navigator.pop(context, true);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.modelManagement,
          'mnn_model_install_failed',
          data: {'repository': widget.entry.repository},
          error: error,
          stackTrace: stackTrace,
          traceId: widget.entry.repository,
        );
      }
      if (mounted) {
        setState(() {
          _installing = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final errorPresentation = _error == null
        ? null
        : _modelVerificationErrorPresentation(context, _error!);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _RepositorySummaryCard(
              engine: 'MNN',
              collection: widget.entry.collection,
              repository: widget.entry.repository,
              downloads: widget.entry.downloads,
            ),
            const SizedBox(height: 14),
            if (_checking) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
              Text(
                context.l10n.verifyingModelPackage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ] else if (model == null) ...[
              _CatalogNotice(
                icon: Icons.fact_check_outlined,
                message: context.l10n.modelPackageNotVerified,
                secondary: context.l10n.modelPackageVerificationDescription,
                error: _error != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _CatalogNotice(
                  message: errorPresentation!.title,
                  secondary: errorPresentation.description,
                  error: true,
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('verify-taobao-mnn-model'),
                onPressed: _inspect,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(context.l10n.verifyModelPackage),
              ),
            ] else ...[
              _CatalogNotice(message: context.l10n.modelCompatibilityPassed),
              const SizedBox(height: 18),
              _DetailCard(
                children: [
                  _DetailRow(
                    context.l10n.officialMnnCollection,
                    model.collection,
                  ),
                  _DetailRow(context.l10n.source, model.repository),
                  _DetailRow(
                    context.l10n.pinnedCommit,
                    model.revision.substring(0, 12),
                  ),
                  _DetailRow(
                    context.l10n.fileSize,
                    _formatBytes(model.downloadSizeBytes),
                  ),
                  _DetailRow(
                    context.l10n.modelFileCount,
                    context.l10n.fileCountValue(model.files.length),
                  ),
                  _DetailRow(
                    context.l10n.recommendedMemory,
                    context.l10n.memoryAndAbove(
                      _formatBytes(model.recommendedMemoryBytes),
                    ),
                  ),
                  if (model.license.isNotEmpty)
                    _DetailRow(context.l10n.license, model.license),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.modelCapabilities,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CapabilityChip(label: context.l10n.textGenerationCapability),
                  if (model.capabilities.imageInput)
                    _CapabilityChip(label: context.l10n.imageInputCapability),
                  if (model.capabilities.audioInput)
                    _CapabilityChip(label: context.l10n.audioInputCapability),
                  if (model.capabilities.thinking)
                    _CapabilityChip(label: context.l10n.reasoningCapability),
                  if (model.capabilities.toolCalling)
                    _CapabilityChip(label: context.l10n.toolCallingCapability),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _CatalogNotice(
                  message: errorPresentation!.title,
                  secondary: errorPresentation.description,
                  error: true,
                ),
              ],
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _checking ? null : _inspect,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.reverifyModelPackage),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('add-taobao-mnn-model'),
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(context.l10n.addToLanguageModels),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiteRtModelDetailPage extends StatefulWidget {
  final LiteRtCatalogEntry entry;
  final LiteRtCatalogService service;
  final Future<void> Function(LiteRtModelSpec model) onInstall;

  const _LiteRtModelDetailPage({
    required this.entry,
    required this.service,
    required this.onInstall,
  });

  @override
  State<_LiteRtModelDetailPage> createState() => _LiteRtModelDetailPageState();
}

class _LiteRtModelDetailPageState extends State<_LiteRtModelDetailPage> {
  LiteRtModelSpec? _model;
  Object? _error;
  bool _checking = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _model = widget.service.cachedSpec(widget.entry.repository);
  }

  Future<void> _inspect() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final model = await widget.service.inspect(widget.entry, force: true);
      if (mounted) setState(() => _model = model);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.modelManagement,
          'litert_model_package_verification_failed',
          data: {'repository': widget.entry.repository},
          error: error,
          stackTrace: stackTrace,
          traceId: widget.entry.repository,
        );
      }
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final model = _model;
    if (model == null || _installing) return;
    setState(() => _installing = true);
    try {
      await widget.onInstall(model);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final errorPresentation = _error == null
        ? null
        : _modelVerificationErrorPresentation(context, _error!);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _RepositorySummaryCard(
              engine: 'LiteRT-LM',
              collection: widget.entry.collection,
              repository: widget.entry.repository,
              downloads: widget.entry.downloads,
            ),
            const SizedBox(height: 14),
            if (_checking) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
              Text(
                context.l10n.verifyingModelPackage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            ] else if (model == null) ...[
              _CatalogNotice(
                icon: Icons.fact_check_outlined,
                message: context.l10n.modelPackageNotVerified,
                secondary: context.l10n.modelPackageVerificationDescription,
                error: _error != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _CatalogNotice(
                  message: errorPresentation!.title,
                  secondary: errorPresentation.description,
                  error: true,
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('verify-litert-model'),
                onPressed: _inspect,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(context.l10n.verifyModelPackage),
              ),
            ] else ...[
              _CatalogNotice(message: context.l10n.liteRtCompatibilityPassed),
              const SizedBox(height: 18),
              _DetailCard(
                children: [
                  _DetailRow(
                    context.l10n.officialLiteRtCollection,
                    model.collection,
                  ),
                  _DetailRow(context.l10n.source, model.repository),
                  _DetailRow(
                    context.l10n.pinnedCommit,
                    model.revision.substring(0, 12),
                  ),
                  _DetailRow(context.l10n.modelFile, model.file.name),
                  _DetailRow(
                    context.l10n.fileSize,
                    _formatBytes(model.downloadSizeBytes),
                  ),
                  _DetailRow(
                    context.l10n.recommendedMemory,
                    context.l10n.memoryAndAbove(
                      _formatBytes(model.recommendedMemoryBytes),
                    ),
                  ),
                  if (model.license.isNotEmpty)
                    _DetailRow(context.l10n.license, model.license),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.modelCapabilities,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CapabilityChip(label: context.l10n.textGenerationCapability),
                  if (model.capabilities.imageInput)
                    _CapabilityChip(label: context.l10n.imageInputCapability),
                  if (model.capabilities.audioInput)
                    _CapabilityChip(label: context.l10n.audioInputCapability),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _CatalogNotice(
                  message: errorPresentation!.title,
                  secondary: errorPresentation.description,
                  error: true,
                ),
              ],
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _checking ? null : _inspect,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.reverifyModelPackage),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('add-litert-model'),
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(context.l10n.addToLanguageModels),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogNotice extends StatelessWidget {
  final String message;
  final String? secondary;
  final bool error;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  const _CatalogNotice({
    required this.message,
    this.secondary,
    this.error = false,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: error ? AppColors.softCoral : AppColors.softGreen,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon ??
              (error ? Icons.error_outline_rounded : Icons.verified_outlined),
          size: 19,
          color: error ? AppColors.coral : AppColors.moss,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(height: 1.4)),
              if (secondary != null) ...[
                const SizedBox(height: 3),
                Text(
                  secondary!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              if (onAction != null || onSecondaryAction != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (onAction != null)
                      TextButton(
                        onPressed: onAction,
                        child: Text(actionLabel ?? context.l10n.retry),
                      ),
                    if (onSecondaryAction != null)
                      TextButton(
                        onPressed: onSecondaryAction,
                        child: Text(secondaryActionLabel ?? ''),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _CatalogErrorPresentation {
  final String title;
  final String description;

  const _CatalogErrorPresentation(this.title, this.description);
}

_CatalogErrorPresentation _catalogErrorPresentation(
  BuildContext context,
  Object error,
) {
  final l10n = context.l10n;
  final kind = error is ModelCatalogRequestException
      ? error.kind
      : error is FormatException ||
            error is TaobaoMnnCatalogException ||
            error is LiteRtCatalogException
      ? ModelCatalogFailureKind.invalidResponse
      : ModelCatalogFailureKind.serviceUnavailable;
  return switch (kind) {
    ModelCatalogFailureKind.timeout => _CatalogErrorPresentation(
      l10n.modelCatalogRefreshTimeout,
      l10n.modelCatalogRefreshTimeoutDescription,
    ),
    ModelCatalogFailureKind.offline => _CatalogErrorPresentation(
      l10n.modelCatalogOffline,
      l10n.modelCatalogOfflineDescription,
    ),
    ModelCatalogFailureKind.unauthorized => _CatalogErrorPresentation(
      l10n.modelCatalogAuthorizationRequired,
      l10n.modelCatalogAuthorizationRequiredDescription,
    ),
    ModelCatalogFailureKind.invalidResponse => _CatalogErrorPresentation(
      l10n.modelCatalogInvalidResponse,
      l10n.modelCatalogInvalidResponseDescription,
    ),
    ModelCatalogFailureKind.serviceUnavailable => _CatalogErrorPresentation(
      l10n.modelCatalogServiceUnavailable,
      l10n.modelCatalogServiceUnavailableDescription,
    ),
  };
}

_CatalogErrorPresentation _modelVerificationErrorPresentation(
  BuildContext context,
  Object error,
) {
  if (error is TaobaoMnnCatalogException || error is LiteRtCatalogException) {
    return _CatalogErrorPresentation(
      context.l10n.modelPackageUnsupported,
      context.l10n.modelPackageUnsupportedDescription,
    );
  }
  return _catalogErrorPresentation(context, error);
}

String _sourceTitle(
  BuildContext context,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic =>
    context.l10n.downloadSourceAutomatic,
  ModelDownloadSourcePreference.officialFirst =>
    context.l10n.downloadSourceOfficialFirst,
  ModelDownloadSourcePreference.mainlandFirst =>
    context.l10n.downloadSourceMainlandFirst,
};

String _sourceDescription(
  BuildContext context,
  ModelDownloadSourcePreference preference,
) => switch (preference) {
  ModelDownloadSourcePreference.automatic =>
    context.l10n.downloadSourceAutomaticDescription,
  ModelDownloadSourcePreference.officialFirst =>
    context.l10n.downloadSourceOfficialDescription,
  ModelDownloadSourcePreference.mainlandFirst =>
    context.l10n.downloadSourceMainlandDescription,
};

IconData _sourceIcon(ModelDownloadSourcePreference preference) =>
    switch (preference) {
      ModelDownloadSourcePreference.automatic => Icons.alt_route_rounded,
      ModelDownloadSourcePreference.officialFirst => Icons.public_rounded,
      ModelDownloadSourcePreference.mainlandFirst => Icons.speed_rounded,
    };

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(children: children),
  );
}

class _RepositorySummaryCard extends StatelessWidget {
  final String engine;
  final String collection;
  final String repository;
  final int downloads;

  const _RepositorySummaryCard({
    required this.engine,
    required this.collection,
    required this.repository,
    required this.downloads,
  });

  @override
  Widget build(BuildContext context) => _DetailCard(
    children: [
      _DetailRow(context.l10n.modelEngine, engine),
      _DetailRow(context.l10n.collection, collection),
      _DetailRow(context.l10n.source, repository),
      if (downloads > 0)
        _DetailRow(
          context.l10n.downloads,
          context.l10n.downloadCount(downloads),
        ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _CapabilityChip extends StatelessWidget {
  final String label;
  const _CapabilityChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.moss,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(1)} GB';
  return '${(bytes / mib).toStringAsFixed(bytes >= 100 * mib ? 0 : 1)} MB';
}
