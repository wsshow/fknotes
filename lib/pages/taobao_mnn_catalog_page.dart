import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/taobao_mnn_model.dart';
import '../services/language_model_service.dart';
import '../services/local_model_manager.dart';
import '../services/taobao_mnn_catalog_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/editor_context_menu.dart';

class TaobaoMnnCatalogPage extends StatefulWidget {
  final TaobaoMnnCatalogService? service;
  final Set<String>? curatedRepositories;
  final Future<void> Function(TaobaoMnnModelSpec model)? onInstall;

  const TaobaoMnnCatalogPage({
    super.key,
    this.service,
    this.curatedRepositories,
    this.onInstall,
  });

  @override
  State<TaobaoMnnCatalogPage> createState() => _TaobaoMnnCatalogPageState();
}

class _TaobaoMnnCatalogPageState extends State<TaobaoMnnCatalogPage> {
  late final TaobaoMnnCatalogService _service;
  late final Set<String> _curatedRepositories;
  final _search = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TaobaoMnnCatalogService.instance;
    _curatedRepositories =
        widget.curatedRepositories ??
        LanguageModelService.instance.curatedRepositories;
    _search.addListener(_changed);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await _service.loadCache();
    if (!mounted) return;
    setState(() => _loading = false);
    if (_service.entries.isEmpty) await _sync();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      await _service.sync();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<TaobaoMnnCatalogEntry> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    return _service.entries.where((entry) {
      if (_curatedRepositories.contains(entry.repository.toLowerCase())) {
        return false;
      }
      return query.isEmpty ||
          entry.name.toLowerCase().contains(query) ||
          entry.collection.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _open(TaobaoMnnCatalogEntry entry) async {
    final installed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _TaobaoMnnModelDetailPage(
          entry: entry,
          service: _service,
          onInstall: widget.onInstall ?? _install,
        ),
      ),
    );
    if (installed == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _install(TaobaoMnnModelSpec model) async {
    final manager = LocalModelManager.instance;
    await manager.registerRemoteModel(model);
    unawaited(manager.download(model.id));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
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
                        message: context.l10n.modelCatalogSyncFailed(_error!),
                        secondary: _service.entries.isEmpty
                            ? null
                            : context.l10n.cachedCatalogInUse,
                        error: true,
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

class _CatalogModelCard extends StatelessWidget {
  final TaobaoMnnCatalogEntry entry;
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
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_inspect());
  }

  Future<void> _inspect() async {
    try {
      final model = await widget.service.inspect(widget.entry);
      if (mounted) setState(() => _model = model);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            if (model == null && _error == null) ...[
              const SizedBox(height: 80),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 18),
              Center(child: Text(context.l10n.checkingModelCompatibility)),
            ] else if (_error != null && model == null)
              EmptyState(
                icon: Icons.error_outline_rounded,
                message: context.l10n.modelCompatibilityFailed(_error!),
                actionLabel: context.l10n.retry,
                onAction: () {
                  setState(() => _error = null);
                  unawaited(_inspect());
                },
              )
            else if (model != null) ...[
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
                _CatalogNotice(message: _error!, error: true),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                key: const Key('add-taobao-mnn-model'),
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(context.l10n.addAndDownloadModel),
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

  const _CatalogNotice({
    required this.message,
    this.secondary,
    this.error = false,
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
          error ? Icons.error_outline_rounded : Icons.verified_outlined,
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
            ],
          ),
        ),
      ],
    ),
  );
}

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
