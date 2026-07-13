import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error, fatal }

enum AppLogCategory {
  application,
  navigation,
  storage,
  database,
  editor,
  media,
  localAssistant,
  inference,
  modelManagement,
  modelDownload,
  speech,
  cloudSync,
  authentication,
  backgroundTask,
  network,
  platform,
}

@immutable
class AppLogRecord {
  final int sequence;
  final DateTime timestamp;
  final Duration elapsed;
  final String sessionId;
  final AppLogLevel level;
  final AppLogCategory category;
  final String event;
  final String? traceId;
  final Map<String, Object?> data;
  final String? error;
  final String? stackTrace;

  const AppLogRecord({
    required this.sequence,
    required this.timestamp,
    required this.elapsed,
    required this.sessionId,
    required this.level,
    required this.category,
    required this.event,
    required this.traceId,
    required this.data,
    required this.error,
    required this.stackTrace,
  });

  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    'sessionId': sessionId,
    'level': level.name,
    'category': category.name,
    'event': event,
    if (traceId != null) 'traceId': traceId,
    if (data.isNotEmpty) 'data': data,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };
}

abstract interface class AppDiagnosticsBackend {
  bool get enabled;
  String get sessionId;
  Listenable get changes;

  Future<void> initialize();

  void record(
    AppLogLevel level,
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
  });

  List<AppLogRecord> snapshot({
    Set<AppLogLevel>? levels,
    Set<AppLogCategory>? categories,
    String query = '',
  });

  Future<void> flush();
  Future<void> clear();
  Future<File?> exportBundle();
}
