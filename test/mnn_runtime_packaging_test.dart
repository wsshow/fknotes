import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android pins the upstream Gemma 4 validated monolithic runtime', () {
    final preparation = File('tool/prepare_mnn_runtime.sh').readAsStringSync();
    final cmake = File(
      'android/app/src/main/cpp/CMakeLists.txt',
    ).readAsStringSync();

    expect(preparation, contains('ANDROID_APP_VERSION="0_8_3"'));
    expect(preparation, contains('mnn_chat_\${ANDROID_APP_VERSION}.apk'));
    expect(
      preparation,
      contains(
        'eb249cabbf73b8b1567d7611715cad8f1cbf4df7be75cb447ea206f12f94ab14',
      ),
    );
    expect(preparation, contains('lib/arm64-v8a/libMNN.so'));
    expect(cmake, contains('MNN_SEP_BUILD=OFF'));
    expect(cmake, isNot(contains('libllm.so')));
  });
}
