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
    expect(service, contains('private lateinit var messenger: Messenger'));
    expect(service, contains('Handler(Looper.getMainLooper())'));
    expect(service, isNot(contains('Handler(mainLooper)')));
    expect(service, isNot(contains('private val messenger = Messenger')));
    expect(service, contains('private data class Command('));
    expect(service, contains('requestId = message.data.getInt('));
    expect(service, contains('replyTo = message.replyTo'));
    expect(service, contains('command.replyTo?.send(response)'));
    expect(service, isNot(contains('operation(message, JSONObject(payload))')));
    expect(
      service,
      contains(
        'LiteRtLmIpc.CANCEL -> execute(message, ::cancel, controlExecutor)',
      ),
    );
    expect(service, contains('targetExecutor: ExecutorService = executor'));
    expect(service, contains('controlExecutor.shutdownNow()'));
    expect(service, contains('requestedBackend == "gpu" && isEmulator()'));
    expect(service, contains('Build.MODEL.startsWith("sdk_gphone")'));
    expect(service, contains('Build.HARDWARE.contains("ranchu")'));
  });
}
