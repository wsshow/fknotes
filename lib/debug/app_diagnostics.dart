import 'app_diagnostics_types.dart';
import 'app_diagnostics_debug.dart'
    if (dart.vm.product) 'app_diagnostics_noop.dart'
    if (dart.vm.profile) 'app_diagnostics_noop.dart'
    as implementation;

export 'app_diagnostics_types.dart';

class AppDiagnostics {
  AppDiagnostics._();

  static AppDiagnosticsBackend get instance => implementation.backend;

  static void debug(
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    String? traceId,
  }) => instance.record(
    AppLogLevel.debug,
    category,
    event,
    data: data,
    traceId: traceId,
  );

  static void info(
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    String? traceId,
  }) => instance.record(
    AppLogLevel.info,
    category,
    event,
    data: data,
    traceId: traceId,
  );

  static void warning(
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
  }) => instance.record(
    AppLogLevel.warning,
    category,
    event,
    data: data,
    error: error,
    stackTrace: stackTrace,
    traceId: traceId,
  );

  static void error(
    AppLogCategory category,
    String event, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? traceId,
    bool fatal = false,
  }) => instance.record(
    fatal ? AppLogLevel.fatal : AppLogLevel.error,
    category,
    event,
    data: data,
    error: error,
    stackTrace: stackTrace,
    traceId: traceId,
  );
}
