import 'package:flutter/services.dart';

enum AndroidExternalDropEventType { entered, updated, exited, done }

final class AndroidDroppedFile {
  const AndroidDroppedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.byteLength,
  });

  final String path;
  final String name;
  final String mimeType;
  final int byteLength;
}

final class AndroidExternalDropEvent {
  const AndroidExternalDropEvent({
    required this.type,
    required this.physicalPosition,
    this.files = const [],
    this.rejectedCount = 0,
  });

  final AndroidExternalDropEventType type;
  final Offset physicalPosition;
  final List<AndroidDroppedFile> files;
  final int rejectedCount;
}

typedef AndroidExternalDropListener =
    void Function(AndroidExternalDropEvent event);

final class AndroidExternalDropService {
  AndroidExternalDropService._();

  static final instance = AndroidExternalDropService._();
  static const _channel = MethodChannel('fknotes/external_image_drop');

  final Set<AndroidExternalDropListener> _listeners = {};
  var _initialized = false;

  void addListener(AndroidExternalDropListener listener) {
    _listeners.add(listener);
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void removeListener(AndroidExternalDropListener listener) {
    _listeners.remove(listener);
  }

  Future<void> deleteTemporaryFiles(Iterable<String> paths) async {
    final values = paths
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) return;
    await _channel.invokeMethod<void>('deleteTemporaryFiles', values);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final map = arguments.cast<Object?, Object?>();
    final position = _positionFrom(map['position']);
    final event = switch (call.method) {
      'entered' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.entered,
        physicalPosition: position,
      ),
      'updated' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.updated,
        physicalPosition: position,
      ),
      'exited' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.exited,
        physicalPosition: position,
      ),
      'done' => AndroidExternalDropEvent(
        type: AndroidExternalDropEventType.done,
        physicalPosition: position,
        files: _filesFrom(map['files']),
        rejectedCount: (map['rejectedCount'] as num?)?.toInt() ?? 0,
      ),
      _ => null,
    };
    if (event == null) return;
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }

  static Offset _positionFrom(Object? value) {
    if (value is! List || value.length < 2) return Offset.zero;
    return Offset(
      (value[0] as num?)?.toDouble() ?? 0,
      (value[1] as num?)?.toDouble() ?? 0,
    );
  }

  static List<AndroidDroppedFile> _filesFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) {
          final map = raw.cast<Object?, Object?>();
          return AndroidDroppedFile(
            path: map['path'] as String? ?? '',
            name: map['name'] as String? ?? '',
            mimeType: map['mimeType'] as String? ?? '',
            byteLength: (map['byteLength'] as num?)?.toInt() ?? 0,
          );
        })
        .where((file) => file.path.isNotEmpty)
        .toList(growable: false);
  }
}
