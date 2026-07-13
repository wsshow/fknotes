import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins official LiteRT-LM and isolates its Android worker', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/fknotes/app/LiteRtLmService.kt',
    ).readAsStringSync();

    expect(
      gradle,
      contains('com.google.ai.edge.litertlm:litertlm-android:0.14.0'),
    );
    expect(manifest, contains('android:process=":local_llm"'));
    expect(manifest, contains('android:exported="false"'));
    expect(service, contains('EngineConfig('));
    expect(service, contains('Content.ImageFile'));
    expect(service, contains('Content.AudioFile'));
  });
}
