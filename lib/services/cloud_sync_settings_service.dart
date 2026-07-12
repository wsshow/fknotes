import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/cloud_sync.dart';
import 'file_storage_service.dart';

class CloudSyncSettingsService {
  CloudSyncSettingsService({String? settingsPath})
    : _settingsPathOverride = settingsPath;

  static final CloudSyncSettingsService instance = CloudSyncSettingsService();

  final String? _settingsPathOverride;
  Future<void> _writeQueue = Future.value();

  String get _settingsPath =>
      _settingsPathOverride ??
      p.join(
        FileStorageService.instance.baseDir,
        'settings',
        'cloud-sync.json',
      );

  Future<CloudSyncSettings> load() async {
    final file = File(_settingsPath);
    CloudSyncSettings settings;
    try {
      settings = await file.exists()
          ? CloudSyncSettings.fromJson(jsonDecode(await file.readAsString()))
          : const CloudSyncSettings();
    } on FormatException {
      settings = const CloudSyncSettings();
    } on FileSystemException {
      settings = const CloudSyncSettings();
    }
    if (settings.deviceId.isNotEmpty) return settings;
    final initialized = settings.copyWith(deviceId: const Uuid().v4());
    await save(initialized);
    return initialized;
  }

  Future<void> save(CloudSyncSettings settings) {
    final operation = _writeQueue.then((_) => _write(settings));
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _write(CloudSyncSettings settings) async {
    final destination = File(_settingsPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }
}
