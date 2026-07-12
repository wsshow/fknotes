import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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

  FfiMnnNativeTransport() {
    _callback = NativeCallable<_NativeEventCallback>.listener(
      _handleNativeEvent,
    );
    try {
      _bindings = _MnnBindings(_openLibrary());
    } catch (_) {
      _bindings = null;
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
      return bindings.load(
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
    try {
      for (var index = 0; index < count; index++) {
        roles[index] = request.messages[index].role.name.toNativeUtf8();
        contents[index] = request.messages[index].content.toNativeUtf8();
      }
      final options = request.options;
      return bindings.generate(
            requestId,
            roles,
            contents,
            count,
            options.maxNewTokens,
            options.temperature,
            options.topP,
            options.topK,
            options.timeout.inMilliseconds,
            _callback.nativeFunction,
          ) ==
          1;
    } finally {
      for (var index = 0; index < count; index++) {
        calloc.free(roles[index]);
        calloc.free(contents[index]);
      }
      calloc.free(roles);
      calloc.free(contents);
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
    var payload = '';
    try {
      if (data.address != 0 && dataSize > 0) {
        payload = utf8.decode(data.asTypedList(dataSize), allowMalformed: true);
      }
    } finally {
      if (data.address != 0) bindings?.free(data.cast());
    }
    if (eventType < 0 || eventType >= MnnNativeEventType.values.length) {
      return;
    }
    _events.add(
      MnnNativeEvent(
        requestId: requestId,
        type: MnnNativeEventType.values[eventType],
        data: payload,
      ),
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
