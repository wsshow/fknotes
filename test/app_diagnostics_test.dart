import 'dart:convert';
import 'dart:io';

import 'package:fknotes/debug/app_diagnostics_debug.dart';
import 'package:fknotes/debug/app_diagnostics_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'debug diagnostics redacts secrets and persists structured events',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fknotes_diagnostics_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final diagnostics = DebugAppDiagnostics(
        supportDirectoryOverride: directory,
        temporaryDirectoryOverride: directory,
      );

      await diagnostics.initialize();
      diagnostics.record(
        AppLogLevel.error,
        AppLogCategory.cloudSync,
        'connection_failed',
        data: {
          'provider': 'S3',
          'secretAccessKey': 'must-not-leak',
          'endpoint': 'https://user:password@example.com/bucket',
          'filePath': '/data/user/0/com.fknotes.app/files/private-note.md',
          'ownerId': '/data/user/0/com.fknotes.app/files/audio/private.m4a',
        },
        error:
            'Authorization: Bearer abc.def.123 at '
            '/data/user/0/com.fknotes.app/files/audio/private.m4a',
        stackTrace: StackTrace.current,
        traceId: 'sync-42',
      );
      await diagnostics.flush();

      final records = diagnostics.snapshot(
        categories: {AppLogCategory.cloudSync},
      );
      expect(records, hasLength(1));
      expect(records.single.data['secretAccessKey'], '<redacted>');
      expect(records.single.data['filePath'], '<redacted>');
      expect(records.single.data['ownerId'], '<redacted>');
      expect(records.single.data['endpoint'], contains('<redacted>@'));
      expect(records.single.error, contains('Bearer <redacted>'));
      expect(records.single.error, isNot(contains('abc.def.123')));
      expect(records.single.error, contains('<private-file>'));
      expect(records.single.error, isNot(contains('private.m4a')));
      final files = await directory
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files, isNotEmpty);
      final lines = await files.single.readAsLines();
      final decoded = lines.map(jsonDecode).whereType<Map>().toList();
      expect(
        decoded.any((event) => event['event'] == 'connection_failed'),
        isTrue,
      );
      expect(
        await files.single.readAsString(),
        isNot(contains('must-not-leak')),
      );
    },
  );

  test('debug diagnostics supports category, level and text filters', () {
    final diagnostics = DebugAppDiagnostics();
    diagnostics.record(
      AppLogLevel.info,
      AppLogCategory.modelManagement,
      'model_selected',
      data: {'modelId': 'qwen-test'},
    );
    diagnostics.record(
      AppLogLevel.warning,
      AppLogCategory.speech,
      'audio_level_low',
    );

    expect(
      diagnostics.snapshot(
        levels: {AppLogLevel.warning},
        categories: {AppLogCategory.speech},
      ),
      hasLength(1),
    );
    expect(diagnostics.snapshot(query: 'qwen-test'), hasLength(1));
    expect(diagnostics.snapshot(query: 'not-present'), isEmpty);
  });
}
