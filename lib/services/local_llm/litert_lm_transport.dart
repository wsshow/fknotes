import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
    try {
      return await _methods.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
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
