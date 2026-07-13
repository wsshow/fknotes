import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../debug/app_diagnostics.dart';
import '../../models/local_llm.dart';

enum MnnNativeEventType {
  loaded,
  textDelta,
  completed,
  canceled,
  unloaded,
  error,
}

class MnnNativeEvent {
  final int requestId;
  final MnnNativeEventType type;
  final String data;

  const MnnNativeEvent({
    required this.requestId,
    required this.type,
    this.data = '',
  });
}

abstract interface class MnnNativeTransport {
  bool get available;
  String get version;
  Stream<MnnNativeEvent> get events;

  bool load({
    required int requestId,
    required String configPath,
    required String cachePath,
    required LocalLlmLoadOptions options,
  });

  bool generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  });

  bool cancel(int requestId);
  bool unload(int requestId);
}

typedef _NativeEventCallback =
    Void Function(Int64, Int32, Pointer<Uint8>, Int32);
typedef _IsAvailableNative = Int32 Function();
typedef _IsAvailableDart = int Function();
typedef _RuntimeVersionNative = Pointer<Utf8> Function();
typedef _RuntimeVersionDart = Pointer<Utf8> Function();
typedef _LoadNative =
    Int32 Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Int32,
      Int32,
      Int32,
      Pointer<NativeFunction<_NativeEventCallback>>,
    );
typedef _LoadDart =
    int Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      int,
      int,
      int,
      Pointer<NativeFunction<_NativeEventCallback>>,
    );
typedef _GenerateNative =
    Int32 Function(
      Int64,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Int32,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Int32>,
      Int32,
      Int32,
      Double,
      Double,
      Int32,
      Int64,
      Pointer<NativeFunction<_NativeEventCallback>>,
    );
typedef _GenerateDart =
    int Function(
      int,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      int,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Int32>,
      int,
      int,
      double,
      double,
      int,
      int,
      Pointer<NativeFunction<_NativeEventCallback>>,
    );
typedef _CancelNative = Int32 Function(Int64);
typedef _CancelDart = int Function(int);
typedef _UnloadNative =
    Int32 Function(Int64, Pointer<NativeFunction<_NativeEventCallback>>);
typedef _UnloadDart =
    int Function(int, Pointer<NativeFunction<_NativeEventCallback>>);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

class FfiMnnNativeTransport implements MnnNativeTransport {
  final _events = StreamController<MnnNativeEvent>.broadcast();
  late final NativeCallable<_NativeEventCallback> _callback;
  _MnnBindings? _bindings;
  final Map<int, MnnUtf8StreamDecoder> _textDecoders = {};

  FfiMnnNativeTransport() {
    _callback = NativeCallable<_NativeEventCallback>.listener(
      _handleNativeEvent,
    );
    try {
      _bindings = _MnnBindings(_openLibrary());
    } catch (error, stackTrace) {
      _bindings = null;
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.platform,
          'mnn_native_library_load_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @override
  bool get available => _bindings?.isAvailable() == 1;

  @override
  String get version {
    final bindings = _bindings;
    if (bindings == null) return '';
    return bindings.runtimeVersion().toDartString();
  }

  @override
  Stream<MnnNativeEvent> get events => _events.stream;

  @override
  bool load({
    required int requestId,
    required String configPath,
    required String cachePath,
    required LocalLlmLoadOptions options,
  }) {
    final bindings = _bindings;
    if (bindings == null) return false;
    final config = configPath.toNativeUtf8();
    final cache = cachePath.toNativeUtf8();
    final backend = _backendName(options.backend).toNativeUtf8();
    try {
      final accepted =
          bindings.load(
            requestId,
            config,
            cache,
            backend,
            options.threads,
            options.contextTokens,
            options.enableThinking ? 1 : 0,
            options.enablePromptCache ? 1 : 0,
            _callback.nativeFunction,
          ) ==
          1;
      if (kDebugMode) {
        AppDiagnostics.debug(
          AppLogCategory.platform,
          'mnn_native_load_dispatched',
          data: {
            'requestId': requestId,
            'accepted': accepted,
            'backend': options.backend.name,
            'threads': options.threads,
            'contextTokens': options.contextTokens,
          },
          traceId: 'mnn-$requestId',
        );
      }
      return accepted;
    } finally {
      calloc.free(config);
      calloc.free(cache);
      calloc.free(backend);
    }
  }

  @override
  bool generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  }) {
    final bindings = _bindings;
    if (bindings == null) return false;
    final count = request.messages.length;
    final roles = calloc<Pointer<Utf8>>(count);
    final contents = calloc<Pointer<Utf8>>(count);
    final attachmentCount = request.messages.fold<int>(
      0,
      (total, message) => total + message.attachments.length,
    );
    final attachmentPaths = attachmentCount == 0
        ? nullptr
        : calloc<Pointer<Utf8>>(attachmentCount);
    final attachmentMimeTypes = attachmentCount == 0
        ? nullptr
        : calloc<Pointer<Utf8>>(attachmentCount);
    final attachmentMessageIndexes = attachmentCount == 0
        ? nullptr
        : calloc<Int32>(attachmentCount);
    try {
      var attachmentIndex = 0;
      for (var index = 0; index < count; index++) {
        roles[index] = request.messages[index].role.name.toNativeUtf8();
        contents[index] = request.messages[index].content.toNativeUtf8();
        for (final attachment in request.messages[index].attachments) {
          attachmentPaths[attachmentIndex] = attachment.path.toNativeUtf8();
          attachmentMimeTypes[attachmentIndex] = attachment.mimeType
              .toNativeUtf8();
          attachmentMessageIndexes[attachmentIndex] = index;
          attachmentIndex++;
        }
      }
      final options = request.options;
      final accepted =
          bindings.generate(
            requestId,
            roles,
            contents,
            count,
            attachmentPaths,
            attachmentMimeTypes,
            attachmentMessageIndexes,
            attachmentCount,
            options.maxNewTokens,
            options.temperature,
            options.topP,
            options.topK,
            options.timeout.inMilliseconds,
            _callback.nativeFunction,
          ) ==
          1;
      if (kDebugMode) {
        AppDiagnostics.debug(
          AppLogCategory.platform,
          'mnn_native_generation_dispatched',
          data: {
            'requestId': requestId,
            'accepted': accepted,
            'messageCount': count,
            'attachmentCount': attachmentCount,
            'maxNewTokens': options.maxNewTokens,
          },
          traceId: 'mnn-$requestId',
        );
      }
      return accepted;
    } finally {
      for (var index = 0; index < count; index++) {
        calloc.free(roles[index]);
        calloc.free(contents[index]);
      }
      for (var index = 0; index < attachmentCount; index++) {
        calloc.free(attachmentPaths[index]);
        calloc.free(attachmentMimeTypes[index]);
      }
      calloc.free(roles);
      calloc.free(contents);
      if (attachmentCount > 0) {
        calloc.free(attachmentPaths);
        calloc.free(attachmentMimeTypes);
        calloc.free(attachmentMessageIndexes);
      }
    }
  }

  @override
  bool cancel(int requestId) => _bindings?.cancel(requestId) == 1;

  @override
  bool unload(int requestId) {
    final bindings = _bindings;
    if (bindings == null) return false;
    return bindings.unload(requestId, _callback.nativeFunction) == 1;
  }

  void _handleNativeEvent(
    int requestId,
    int eventType,
    Pointer<Uint8> data,
    int dataSize,
  ) {
    final bindings = _bindings;
    late final List<int> bytes;
    try {
      bytes = data.address != 0 && dataSize > 0
          ? List<int>.of(data.asTypedList(dataSize))
          : const [];
    } finally {
      if (data.address != 0) bindings?.free(data.cast());
    }
    if (eventType < 0 || eventType >= MnnNativeEventType.values.length) {
      return;
    }
    final type = MnnNativeEventType.values[eventType];
    if (kDebugMode && type != MnnNativeEventType.textDelta) {
      final failed = type == MnnNativeEventType.error;
      AppDiagnostics.instance.record(
        failed ? AppLogLevel.error : AppLogLevel.debug,
        AppLogCategory.inference,
        'mnn_native_event',
        data: {
          'requestId': requestId,
          'type': type.name,
          if (!failed) 'payloadBytes': bytes.length,
        },
        error: failed ? utf8.decode(bytes, allowMalformed: true) : null,
        traceId: 'mnn-$requestId',
      );
    }
    if (type == MnnNativeEventType.textDelta) {
      try {
        final payload = _textDecoders
            .putIfAbsent(requestId, MnnUtf8StreamDecoder.new)
            .add(bytes);
        if (payload.isNotEmpty) {
          _events.add(
            MnnNativeEvent(
              requestId: requestId,
              type: MnnNativeEventType.textDelta,
              data: payload,
            ),
          );
        }
      } on FormatException {
        _textDecoders.remove(requestId);
        _events.add(
          MnnNativeEvent(
            requestId: requestId,
            type: MnnNativeEventType.error,
            data: 'MNN 返回了无效的 UTF-8 文本',
          ),
        );
      }
      return;
    }
    final decoder = _textDecoders.remove(requestId);
    if (type == MnnNativeEventType.completed && decoder != null) {
      try {
        final finalText = decoder.close();
        if (finalText.isNotEmpty) {
          _events.add(
            MnnNativeEvent(
              requestId: requestId,
              type: MnnNativeEventType.textDelta,
              data: finalText,
            ),
          );
        }
      } on FormatException {
        _events.add(
          MnnNativeEvent(
            requestId: requestId,
            type: MnnNativeEventType.error,
            data: 'MNN 输出在 UTF-8 字符中间意外结束',
          ),
        );
        return;
      }
    }
    String payload;
    try {
      payload = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      _events.add(
        MnnNativeEvent(
          requestId: requestId,
          type: MnnNativeEventType.error,
          data: 'MNN 返回了无法解码的事件数据',
        ),
      );
      return;
    }
    _events.add(
      MnnNativeEvent(requestId: requestId, type: type, data: payload),
    );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) return DynamicLibrary.open('libfknotes_mnn.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    throw UnsupportedError('MNN is only bundled on Android and iOS');
  }

  static String _backendName(LocalLlmBackend backend) => switch (backend) {
    LocalLlmBackend.cpu => 'cpu',
    LocalLlmBackend.openCl => 'opencl',
    LocalLlmBackend.vulkan => 'vulkan',
    LocalLlmBackend.metal => 'metal',
  };
}

/// Incrementally decodes UTF-8 without replacing a character that straddles
/// native callback boundaries.
class MnnUtf8StreamDecoder {
  final List<int> _pending = [];
  bool _closed = false;

  String add(List<int> bytes) {
    if (_closed) throw StateError('UTF-8 decoder is already closed');
    _pending.addAll(bytes);
    final completeLength = _completePrefixLength(_pending);
    if (completeLength == 0) return '';
    final complete = _pending.sublist(0, completeLength);
    _pending.removeRange(0, completeLength);
    return utf8.decode(complete, allowMalformed: false);
  }

  String close() {
    if (_closed) return '';
    _closed = true;
    if (_pending.isEmpty) return '';
    final completeLength = _completePrefixLength(_pending);
    if (completeLength != _pending.length) {
      throw const FormatException('Incomplete UTF-8 character');
    }
    final result = utf8.decode(_pending, allowMalformed: false);
    _pending.clear();
    return result;
  }

  static int _completePrefixLength(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    var start = bytes.length - 1;
    while (start > 0 && (bytes[start] & 0xC0) == 0x80) {
      start--;
    }
    final lead = bytes[start];
    final expected = (lead & 0xE0) == 0xC0
        ? 2
        : (lead & 0xF0) == 0xE0
        ? 3
        : (lead & 0xF8) == 0xF0
        ? 4
        : 1;
    return bytes.length - start < expected ? start : bytes.length;
  }
}

class _MnnBindings {
  late final _IsAvailableDart isAvailable;
  late final _RuntimeVersionDart runtimeVersion;
  late final _LoadDart load;
  late final _GenerateDart generate;
  late final _CancelDart cancel;
  late final _UnloadDart unload;
  late final _FreeDart free;

  _MnnBindings(DynamicLibrary library) {
    isAvailable = library.lookupFunction<_IsAvailableNative, _IsAvailableDart>(
      'fk_mnn_is_available',
    );
    runtimeVersion = library
        .lookupFunction<_RuntimeVersionNative, _RuntimeVersionDart>(
          'fk_mnn_runtime_version',
        );
    load = library.lookupFunction<_LoadNative, _LoadDart>('fk_mnn_load_async');
    generate = library.lookupFunction<_GenerateNative, _GenerateDart>(
      'fk_mnn_generate_async',
    );
    cancel = library.lookupFunction<_CancelNative, _CancelDart>(
      'fk_mnn_cancel',
    );
    unload = library.lookupFunction<_UnloadNative, _UnloadDart>(
      'fk_mnn_unload_async',
    );
    free = library.lookupFunction<_FreeNative, _FreeDart>('fk_mnn_free');
  }
}
