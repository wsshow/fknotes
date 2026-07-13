import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../debug/app_diagnostics.dart';
import '../../models/local_llm.dart';

enum LiteRtLmNativeEventType {
  loaded,
  textDelta,
  completed,
  canceled,
  unloaded,
  error,
  serviceDied,
}

class LiteRtLmNativeEvent {
  final int requestId;
  final LiteRtLmNativeEventType type;
  final String data;

  const LiteRtLmNativeEvent({
    required this.requestId,
    required this.type,
    this.data = '',
  });
}

abstract interface class LiteRtLmTransport {
  bool get available;
  String get version;
  Stream<LiteRtLmNativeEvent> get events;

  Future<bool> load({
    required int requestId,
    required String modelPath,
    required String cachePath,
    required LocalLlmLoadOptions options,
    required LocalLlmCapabilities capabilities,
  });

  Future<bool> generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  });

  Future<bool> cancel(int requestId);
  Future<bool> unload(int requestId);
}

class MethodChannelLiteRtLmTransport implements LiteRtLmTransport {
  static const _methods = MethodChannel('fknotes/litert_lm');
  static const _nativeEvents = EventChannel('fknotes/litert_lm_events');

  late final Stream<LiteRtLmNativeEvent> _events = _nativeEvents
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => _decodeEvent(Map<Object?, Object?>.from(event as Map)))
      .map((event) {
        if (kDebugMode && event.type != LiteRtLmNativeEventType.textDelta) {
          final failed =
              event.type == LiteRtLmNativeEventType.error ||
              event.type == LiteRtLmNativeEventType.serviceDied;
          AppDiagnostics.instance.record(
            failed ? AppLogLevel.error : AppLogLevel.debug,
            AppLogCategory.inference,
            'litert_native_event',
            data: {
              'requestId': event.requestId,
              'type': event.type.name,
              if (!failed && event.data.isNotEmpty)
                'payloadLength': event.data.length,
            },
            error: failed ? event.data : null,
            traceId: 'litert-${event.requestId}',
          );
        }
        return event;
      })
      .asBroadcastStream();

  @override
  bool get available => Platform.isAndroid;

  @override
  String get version => available ? '0.14.0' : '';

  @override
  Stream<LiteRtLmNativeEvent> get events => _events;

  @override
  Future<bool> load({
    required int requestId,
    required String modelPath,
    required String cachePath,
    required LocalLlmLoadOptions options,
    required LocalLlmCapabilities capabilities,
  }) => _invoke('load', {
    'requestId': requestId,
    'modelPath': modelPath,
    'cachePath': cachePath,
    'backend': options.backend == LocalLlmBackend.cpu ? 'cpu' : 'gpu',
    'threads': options.threads,
    'contextTokens': options.contextTokens,
    'imageInput': capabilities.imageInput,
    'audioInput': capabilities.audioInput,
  });

  @override
  Future<bool> generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  }) => _invoke('generate', {
    'requestId': requestId,
    'messages': [
      for (final message in request.messages)
        {
          'role': message.role.name,
          'content': message.content,
          'attachments': [
            for (final attachment in message.attachments)
              {'path': attachment.path, 'mimeType': attachment.mimeType},
          ],
        },
    ],
    'maxNewTokens': request.options.maxNewTokens,
    'temperature': request.options.temperature,
    'topP': request.options.topP,
    'topK': request.options.topK,
    'timeoutMs': request.options.timeout.inMilliseconds,
  });

  @override
  Future<bool> cancel(int requestId) =>
      _invoke('cancel', {'requestId': requestId});

  @override
  Future<bool> unload(int requestId) =>
      _invoke('unload', {'requestId': requestId});

  Future<bool> _invoke(String method, Map<String, Object?> arguments) async {
    if (!available) return false;
    final requestId = (arguments['requestId'] as num?)?.toInt() ?? -1;
    if (kDebugMode) {
      AppDiagnostics.debug(
        AppLogCategory.platform,
        'litert_method_channel_invoked',
        data: {
          'method': method,
          'requestId': requestId,
          if (method == 'generate')
            'messageCount': (arguments['messages'] as List?)?.length ?? 0,
        },
        traceId: 'litert-$requestId',
      );
    }
    try {
      final accepted =
          await _methods.invokeMethod<bool>(method, arguments) ?? false;
      if (kDebugMode) {
        AppDiagnostics.debug(
          AppLogCategory.platform,
          'litert_method_channel_completed',
          data: {
            'method': method,
            'requestId': requestId,
            'accepted': accepted,
          },
          traceId: 'litert-$requestId',
        );
      }
      return accepted;
    } on MissingPluginException catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.platform,
          'litert_method_channel_missing',
          data: {'method': method, 'requestId': requestId},
          error: error,
          stackTrace: stackTrace,
          traceId: 'litert-$requestId',
        );
      }
      return false;
    } on PlatformException catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.platform,
          'litert_method_channel_failed',
          data: {'method': method, 'requestId': requestId, 'code': error.code},
          error: error,
          stackTrace: stackTrace,
          traceId: 'litert-$requestId',
        );
      }
      return false;
    }
  }

  static LiteRtLmNativeEvent _decodeEvent(Map<Object?, Object?> raw) {
    final typeName = raw['type'] as String? ?? 'error';
    final type = LiteRtLmNativeEventType.values.firstWhere(
      (candidate) => candidate.name == typeName,
      orElse: () => LiteRtLmNativeEventType.error,
    );
    return LiteRtLmNativeEvent(
      requestId: (raw['requestId'] as num?)?.toInt() ?? -1,
      type: type,
      data: raw['data'] as String? ?? '',
    );
  }
}
