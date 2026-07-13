import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_diagnostics_types.dart';

final AppDiagnosticsBackend backend = DebugAppDiagnostics();

@visibleForTesting
class DebugAppDiagnostics extends ChangeNotifier
    implements AppDiagnosticsBackend {
  static const _maxMemoryRecords = 1500;
  static const _maxLogFileBytes = 2 * 1024 * 1024;
  static const _maxPersistedFiles = 6;
  static final _sensitiveKey = RegExp(
    r'(password|passphrase|secret|token|authorization|cookie|credential|access.?key|system.?prompt|content|note.?text|chat.?text|transcript|ocr.?text)',
    caseSensitive: false,
  );
  static final _bearerPattern = RegExp(
    r'(bearer\s+|basic\s+)[a-z0-9+/=._-]+',
    caseSensitive: false,
  );
  static final _urlCredentialPattern = RegExp(r'(?<=://)[^/@\s]+@');

  final _records = <AppLogRecord>[];
  final _clock = Stopwatch()..start();
  final String _sessionId = _newSessionId();
  final Directory? supportDirectoryOverride;
  final Directory? temporaryDirectoryOverride;
  Future<void> _writeTail = Future<void>.value();
  Directory? _directory;
  File? _currentFile;
  int _part = 0;
  int _sequence = 0;
  int _currentBytes = 0;
  bool _initialized = false;

  DebugAppDiagnostics({
    this.supportDirectoryOverride,
    this.temporaryDirectoryOverride,
  });

  @override
  bool get enabled => true;

  @override
  String get sessionId => _sessionId;

  @override
  Listenable get changes => this;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final support =
        supportDirectoryOverride ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'debug_diagnostics'));
    await directory.create(recursive: true);
    _directory = directory;
    await _cleanupOldFiles(directory);
    _currentFile = _fileForPart(directory, _part);
    final existing = List<AppLogRecord>.of(_records);
    if (existing.isNotEmpty) {
      final contents = existing
          .map((item) => jsonEncode(item.toJson()))
          .join('\n');
      await _currentFile!.writeAsString('$contents\n', flush: true);
      _currentBytes = utf8.encode('$contents\n').length;
    }
    _initialized = true;
    record(
      AppLogLevel.info,
      AppLogCategory.application,
      'diagnostics_started',
      data: {
        'sessionId': _sessionId,
        'maxMemoryRecords': _maxMemoryRecords,
        'maxLogFileBytes': _maxLogFileBytes,
      },
    );
  }

  @override
  void record(
    AppLogLevel level,
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
  }) {
    final record = AppLogRecord(
      sequence: ++_sequence,
      timestamp: DateTime.now(),
      elapsed: _clock.elapsed,
      sessionId: _sessionId,
      level: level,
      category: category,
      event: _sanitizeText(event, limit: 160),
      traceId: traceId == null ? null : _sanitizeText(traceId, limit: 100),
      data: _sanitizeMap(data),
      error: error == null ? null : _sanitizeText('$error', limit: 1800),
      stackTrace: stackTrace == null
          ? null
          : _sanitizeText('$stackTrace', limit: 12000),
    );
    _records.add(record);
    if (_records.length > _maxMemoryRecords) {
      _records.removeRange(0, _records.length - _maxMemoryRecords);
    }
    notifyListeners();
    if (level.index >= AppLogLevel.error.index) {
      debugPrint(
        'FKNOTES ${level.name.toUpperCase()} ${category.name}/${record.event}'
        '${record.error == null ? '' : ': ${record.error}'}',
      );
    }
    if (_initialized) _enqueueWrite(record);
  }

  @override
  List<AppLogRecord> snapshot({
    Set<AppLogLevel>? levels,
    Set<AppLogCategory>? categories,
    String query = '',
  }) {
    final normalized = query.trim().toLowerCase();
    return List<AppLogRecord>.unmodifiable(
      _records.where((record) {
        if (levels != null &&
            levels.isNotEmpty &&
            !levels.contains(record.level)) {
          return false;
        }
        if (categories != null &&
            categories.isNotEmpty &&
            !categories.contains(record.category)) {
          return false;
        }
        if (normalized.isEmpty) return true;
        final searchable = [
          record.event,
          record.category.name,
          record.level.name,
          record.traceId,
          record.error,
          jsonEncode(record.data),
        ].whereType<String>().join(' ').toLowerCase();
        return searchable.contains(normalized);
      }),
    );
  }

  @override
  Future<void> flush() => _writeTail;

  @override
  Future<void> clear() async {
    await flush();
    _records.clear();
    _sequence = 0;
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && p.basename(entity.path).startsWith('events-')) {
          await entity.delete();
        }
      }
      _part = 0;
      _currentFile = _fileForPart(directory, _part);
      _currentBytes = 0;
    }
    notifyListeners();
    record(AppLogLevel.info, AppLogCategory.application, 'diagnostics_cleared');
  }

  @override
  Future<File?> exportBundle() async {
    if (!_initialized) await initialize();
    record(
      AppLogLevel.info,
      AppLogCategory.application,
      'diagnostics_export_started',
    );
    await flush();
    final now = DateTime.now();
    final temporary =
        temporaryDirectoryOverride ?? await getTemporaryDirectory();
    final outputDirectory = Directory(
      p.join(temporary.path, 'fknotes_debug_exports'),
    );
    await outputDirectory.create(recursive: true);
    final output = File(
      p.join(outputDirectory.path, 'fknotes-debug-${_fileTimestamp(now)}.zip'),
    );
    final package = await PackageInfo.fromPlatform();
    final encoder = ZipFileEncoder()..create(output.path);
    var open = true;
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(
          'manifest.json',
          const JsonEncoder.withIndent('  ').convert({
            'formatVersion': 1,
            'createdAt': now.toUtc().toIso8601String(),
            'sessionId': _sessionId,
            'app': {
              'name': package.appName,
              'packageName': package.packageName,
              'version': package.version,
              'buildNumber': package.buildNumber,
            },
            'runtime': {
              'operatingSystem': Platform.operatingSystem,
              'operatingSystemVersion': _sanitizeText(
                Platform.operatingSystemVersion,
                limit: 600,
              ),
              'locale': Platform.localeName,
              'numberOfProcessors': Platform.numberOfProcessors,
              'dartVersion': _sanitizeText(Platform.version, limit: 500),
            },
            'privacy': {
              'userContentIncluded': false,
              'credentialsIncluded': false,
              'valuesRedactedByKey': true,
            },
          }),
        ),
      );
      final records = snapshot();
      encoder.addArchiveFile(
        ArchiveFile.string(
          'current-session.jsonl',
          records.map((record) => jsonEncode(record.toJson())).join('\n'),
        ),
      );
      encoder.addArchiveFile(
        ArchiveFile.string(
          'errors.json',
          const JsonEncoder.withIndent(' ').convert(
            records
                .where(
                  (record) => record.level.index >= AppLogLevel.error.index,
                )
                .map((record) => record.toJson())
                .toList(),
          ),
        ),
      );
      final directory = _directory;
      if (directory != null) {
        final files = await directory
            .list(followLinks: false)
            .where((entity) => entity is File)
            .cast<File>()
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          await encoder.addFile(
            file,
            p.join('sessions', p.basename(file.path)),
          );
        }
      }
      await encoder.close();
      open = false;
      record(
        AppLogLevel.info,
        AppLogCategory.application,
        'diagnostics_export_completed',
        data: {'sizeBytes': await output.length()},
      );
      return output;
    } catch (error, stackTrace) {
      record(
        AppLogLevel.error,
        AppLogCategory.application,
        'diagnostics_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (open) {
        try {
          await encoder.close();
        } catch (_) {}
      }
    }
  }

  void _enqueueWrite(AppLogRecord record) {
    final line = '${jsonEncode(record.toJson())}\n';
    final bytes = utf8.encode(line).length;
    _writeTail = _writeTail
        .then((_) async {
          var file = _currentFile;
          final directory = _directory;
          if (file == null || directory == null) return;
          if (_currentBytes + bytes > _maxLogFileBytes) {
            _part++;
            file = _fileForPart(directory, _part);
            _currentFile = file;
            _currentBytes = 0;
            await _cleanupOldFiles(directory);
          }
          await file.writeAsString(line, mode: FileMode.append, flush: true);
          _currentBytes += bytes;
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('FKNOTES diagnostics write failed: $error\n$stackTrace');
        });
  }

  Future<void> _cleanupOldFiles(Directory directory) async {
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(_maxPersistedFiles)) {
      await file.delete();
    }
  }

  File _fileForPart(Directory directory, int part) => File(
    p.join(
      directory.path,
      'events-$_sessionId-${part.toString().padLeft(2, '0')}.jsonl',
    ),
  );

  Map<String, Object?> _sanitizeMap(Map<String, Object?> value) => {
    for (final entry in value.entries)
      _sanitizeText(entry.key, limit: 100): _sensitiveKey.hasMatch(entry.key)
          ? '<redacted>'
          : _sanitizeValue(entry.value, depth: 0),
  };

  Object? _sanitizeValue(Object? value, {required int depth}) {
    if (value == null || value is num || value is bool) return value;
    if (depth >= 5) return '<depth-limit>';
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMilliseconds;
    if (value is String) return _sanitizeText(value, limit: 1000);
    if (value is Map) {
      return {
        for (final entry in value.entries)
          _sanitizeText(
            '${entry.key}',
            limit: 100,
          ): _sensitiveKey.hasMatch('${entry.key}')
              ? '<redacted>'
              : _sanitizeValue(entry.value, depth: depth + 1),
      };
    }
    if (value is Iterable) {
      return value
          .take(50)
          .map((item) => _sanitizeValue(item, depth: depth + 1))
          .toList();
    }
    return _sanitizeText('$value', limit: 1000);
  }

  String _sanitizeText(String value, {required int limit}) {
    var sanitized = value
        .replaceAllMapped(
          _bearerPattern,
          (match) => '${match.group(1)}<redacted>',
        )
        .replaceAll(_urlCredentialPattern, '<redacted>@')
        .replaceAll(Platform.environment['HOME'] ?? '\u0000', '<home>');
    if (sanitized.length > limit) {
      sanitized = '${sanitized.substring(0, limit)}…<truncated>';
    }
    return sanitized;
  }
}

String _newSessionId() {
  final now = DateTime.now().toUtc();
  return '${_fileTimestamp(now)}-${now.microsecondsSinceEpoch.toRadixString(36)}';
}

String _fileTimestamp(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}-'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}';
