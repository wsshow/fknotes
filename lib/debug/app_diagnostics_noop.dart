import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_diagnostics_types.dart';

final AppDiagnosticsBackend backend = _NoopAppDiagnostics();

class _NoopAppDiagnostics implements AppDiagnosticsBackend {
  static const _listenable = _NoopListenable();

  @override
  bool get enabled => false;

  @override
  String get sessionId => '';

  @override
  Listenable get changes => _listenable;

  @override
  Future<void> initialize() async {}

  @override
  void record(
    AppLogLevel level,
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
  }) {}

  @override
  List<AppLogRecord> snapshot({
    Set<AppLogLevel>? levels,
    Set<AppLogCategory>? categories,
    String query = '',
  }) => const [];

  @override
  Future<void> flush() async {}

  @override
  Future<void> clear() async {}

  @override
  Future<File?> exportBundle() async => null;
}

class _NoopListenable implements Listenable {
  const _NoopListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
