import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android pins the generic split MNN 3.6 runtime', () {
    final preparation = File('tool/prepare_mnn_runtime.sh').readAsStringSync();
    final cmake = File(
      'android/app/src/main/cpp/CMakeLists.txt',
    ).readAsStringSync();

    expect(
      preparation,
      contains(
        '3ff2b92e11531f5a9d820b6bf6a8aede3e124e098a3645d8f6a23dcbc862015f',
      ),
    );
    expect(preparation, contains('mnn_\${MNN_VERSION}_android_armv7_armv8'));
    expect(cmake, contains('foreach(library MNN MNN_Express'));
    expect(cmake, contains('llm MNN_Express'));
    expect(preparation, isNot(contains('mnn_chat_')));
    expect(preparation, contains('libllm.so'));
    final bridge = File('native/mnn/fknotes_mnn_bridge.cpp').readAsStringSync();
    expect(
      bridge,
      contains(
        'emit_event(callback, request_id, FK_MNN_EVENT_LOADED, backend)',
      ),
    );
  });
}
