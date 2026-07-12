import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/cloud_sync.dart';
import '../providers/note_provider.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/app_feedback.dart';

class CloudSyncPage extends StatefulWidget {
  final CloudSyncService? service;
  final CloudSyncSettings? initialSettings;
  const CloudSyncPage({super.key, this.service, this.initialSettings});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  CloudSyncService get _service => widget.service ?? CloudSyncService.instance;
  final _webDavUrl = TextEditingController();
  final _webDavUsername = TextEditingController();
  final _webDavPassword = TextEditingController();
  final _webDavFolder = TextEditingController();
  final _s3Endpoint = TextEditingController();
  final _s3Region = TextEditingController();
  final _s3Bucket = TextEditingController();
  final _s3AccessKey = TextEditingController();
  final _s3SecretKey = TextEditingController();
  final _s3Prefix = TextEditingController();

  CloudSyncSettings? _settings;
  CloudSyncProvider _provider = CloudSyncProvider.webDav;
  bool _pathStyle = true;
  bool _busy = false;
  bool _showWebDavPassword = false;
  bool _showS3Secret = false;
  bool _restoredData = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettings;
    if (initial == null) {
      unawaited(_load());
    } else {
      _populate(initial);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _webDavUrl,
      _webDavUsername,
      _webDavPassword,
      _webDavFolder,
      _s3Endpoint,
      _s3Region,
      _s3Bucket,
      _s3AccessKey,
      _s3SecretKey,
      _s3Prefix,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _service.loadSettings();
    if (!mounted) return;
    _apply(settings);
  }

  void _apply(CloudSyncSettings settings) {
    _populate(settings);
    setState(() {});
  }

  void _populate(CloudSyncSettings settings) {
    _webDavUrl.text = settings.webDav.serverUrl;
    _webDavUsername.text = settings.webDav.username;
    _webDavPassword.text = settings.webDav.password;
    _webDavFolder.text = settings.webDav.remoteFolder;
    _s3Endpoint.text = settings.s3.endpoint;
    _s3Region.text = settings.s3.region;
    _s3Bucket.text = settings.s3.bucket;
    _s3AccessKey.text = settings.s3.accessKeyId;
    _s3SecretKey.text = settings.s3.secretAccessKey;
    _s3Prefix.text = settings.s3.prefix;
    _settings = settings;
    _provider = settings.provider;
    _pathStyle = settings.s3.pathStyle;
  }

  CloudSyncSettings _candidate() => CloudSyncSettings(
    provider: _provider,
    webDav: WebDavSyncConfig(
      serverUrl: _webDavUrl.text.trim(),
      username: _webDavUsername.text.trim(),
      password: _webDavPassword.text,
      remoteFolder: _webDavFolder.text.trim(),
    ),
    s3: S3SyncConfig(
      endpoint: _s3Endpoint.text.trim(),
      region: _s3Region.text.trim(),
      bucket: _s3Bucket.text.trim(),
      accessKeyId: _s3AccessKey.text.trim(),
      secretAccessKey: _s3SecretKey.text,
      prefix: _s3Prefix.text.trim(),
      pathStyle: _pathStyle,
    ),
    deviceId: _settings?.deviceId ?? '',
    lastSyncedContentDigest: _settings?.lastSyncedContentDigest,
    lastRemoteRevision: _settings?.lastRemoteRevision,
    lastSyncedAt: _settings?.lastSyncedAt,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) Navigator.pop(context, _restoredData);
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: _busy ? null : () => Navigator.pop(context, _restoredData),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.l10n.cloudSync),
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _InfoCard(settings: _settings!),
                const SizedBox(height: 22),
                Text(
                  context.l10n.syncMethod,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<CloudSyncProvider>(
                  segments: const [
                    ButtonSegment(
                      value: CloudSyncProvider.webDav,
                      label: Text('WebDAV'),
                      icon: Icon(Icons.cloud_outlined),
                    ),
                    ButtonSegment(
                      value: CloudSyncProvider.s3,
                      label: Text('S3'),
                      icon: Icon(Icons.storage_rounded),
                    ),
                  ],
                  selected: {_provider},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() => _provider = value.single),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _provider == CloudSyncProvider.webDav
                      ? _webDavForm()
                      : _s3Form(),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(context.l10n.saveConfiguration),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _testConnection,
                  icon: const Icon(Icons.network_check_rounded),
                  label: Text(context.l10n.testConnection),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _sync,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _busy ? context.l10n.syncing : context.l10n.syncNow,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.manualSyncForegroundHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _webDavForm() => _FormCard(
    key: const ValueKey('webdav'),
    children: [
      _field(
        controller: _webDavUrl,
        label: context.l10n.serverAddress,
        hint: 'https://example.com/dav/',
        keyboardType: TextInputType.url,
      ),
      _field(controller: _webDavUsername, label: context.l10n.username),
      _field(
        controller: _webDavPassword,
        label: context.l10n.passwordOrAppPassword,
        obscureText: !_showWebDavPassword,
        suffix: _visibilityButton(
          _showWebDavPassword,
          () => setState(() => _showWebDavPassword = !_showWebDavPassword),
        ),
      ),
      _field(
        controller: _webDavFolder,
        label: context.l10n.remoteDirectory,
        hint: 'FKNotes',
        textInputAction: TextInputAction.done,
      ),
    ],
  );

  Widget _s3Form() => _FormCard(
    key: const ValueKey('s3'),
    children: [
      _field(
        controller: _s3Endpoint,
        label: 'Endpoint',
        hint: 'https://s3.example.com',
        keyboardType: TextInputType.url,
      ),
      Row(
        children: [
          Expanded(
            child: _field(controller: _s3Region, label: 'Region'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(controller: _s3Bucket, label: 'Bucket'),
          ),
        ],
      ),
      _field(controller: _s3AccessKey, label: 'Access Key ID'),
      _field(
        controller: _s3SecretKey,
        label: 'Secret Access Key',
        obscureText: !_showS3Secret,
        suffix: _visibilityButton(
          _showS3Secret,
          () => setState(() => _showS3Secret = !_showS3Secret),
        ),
      ),
      _field(
        controller: _s3Prefix,
        label: context.l10n.objectPrefix,
        hint: 'FKNotes',
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.pathStyleAddress),
        subtitle: Text(context.l10n.pathStyleDescription),
        value: _pathStyle,
        onChanged: _busy ? null : (value) => setState(() => _pathStyle = value),
      ),
    ],
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _visibilityButton(bool visible, VoidCallback onPressed) => IconButton(
    tooltip: visible ? context.l10n.hide : context.l10n.show,
    onPressed: _busy ? null : onPressed,
    icon: Icon(
      visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
    ),
  );

  Future<void> _save() async {
    await _perform(() async {
      final candidate = _candidate();
      final problem = candidate.configurationProblem;
      if (problem != null) throw StateError(problem);
      final saved = await _service.saveConfiguration(candidate);
      if (!mounted) return;
      setState(() => _settings = saved);
      _message(context.l10n.cloudConfigurationSaved);
    });
  }

  Future<void> _testConnection() async {
    await _perform(() async {
      final candidate = _candidate();
      await _service.testConnection(candidate);
      if (mounted) _message(context.l10n.connectionSuccessful);
    });
  }

  Future<void> _sync() async {
    await _perform(() async {
      final saved = await _service.saveConfiguration(_candidate());
      if (mounted) setState(() => _settings = saved);
      var result = await _service.synchronize();
      if (result.type == CloudSyncResultType.conflict) {
        final resolution = await _askConflict(result.remote!);
        if (resolution == null) return;
        result = await _service.resolveConflict(resolution);
      }
      await _handleResult(result);
    });
  }

  Future<CloudSyncConflictResolution?> _askConflict(
    CloudSnapshotMetadata remote,
  ) => showDialog<CloudSyncConflictResolution>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.syncConflictDetected),
      content: Text(
        context.l10n.syncConflictDescription(
          _formatDate(context, remote.createdAt.toLocal()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.notNow),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, CloudSyncConflictResolution.useRemote),
          child: Text(context.l10n.useCloudVersion),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, CloudSyncConflictResolution.keepLocal),
          child: Text(context.l10n.keepLocalVersion),
        ),
      ],
    ),
  );

  Future<void> _handleResult(CloudSyncResult result) async {
    if (result.type == CloudSyncResultType.downloaded) {
      await context.read<NoteProvider>().loadEntries();
      _restoredData = true;
    }
    final refreshed = await _service.loadSettings();
    if (!mounted) return;
    setState(() => _settings = refreshed);
    _message(switch (result.type) {
      CloudSyncResultType.uploaded => context.l10n.syncedLocalToCloud,
      CloudSyncResultType.downloaded => context.l10n.updatedFromCloud,
      CloudSyncResultType.unchanged => context.l10n.cloudAlreadyUpToDate,
      CloudSyncResultType.conflict => context.l10n.syncConflictUnresolved,
    });
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (error) {
      AppFeedback.error(context, text);
    } else {
      AppFeedback.success(context, text);
    }
  }

  String _friendlyError(Object error) {
    if (error is HandshakeException) return context.l10n.httpsCertificateFailed;
    if (error is SocketException) return context.l10n.cloudConnectionFailed;
    if (error is TimeoutException) {
      return error.message ?? context.l10n.cloudConnectionTimeout;
    }
    return error.toString().replaceFirst(
      RegExp(r'^(Bad state|StateError|Exception|FormatException):\s*'),
      '',
    );
  }

  String _formatDate(BuildContext context, DateTime value) =>
      DateFormat.yMd(context.l10n.localeName).add_Hm().format(value);
}

class _InfoCard extends StatelessWidget {
  final CloudSyncSettings settings;
  const _InfoCard({required this.settings});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.cloud_sync_outlined, color: AppColors.moss),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.manualUserDataSync,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.syncScopeDescription,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.cloudEncryptionWarning,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              if (settings.lastSyncedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.l10n.lastSyncedAt(
                    DateFormat.yMd(
                      context.l10n.localeName,
                    ).add_Hm().format(settings.lastSyncedAt!.toLocal()),
                  ),
                  style: const TextStyle(
                    color: AppColors.moss,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;
  const _FormCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(children: children),
    ),
  );
}
