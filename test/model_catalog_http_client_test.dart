import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/services/model_catalog_http_client.dart';
import 'package:fknotes/services/model_download_source_policy.dart';
import 'package:fknotes/services/model_download_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late String settingsPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_catalog_http_');
    settingsPath = p.join(directory.path, 'network-source.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'automatic mode quickly falls back and remembers the healthy source',
    () async {
      final policy = ModelDownloadSourcePolicy(
        settingsPath: settingsPath,
        countryCodeProvider: () => 'CN',
      );
      final attempts = <ModelDownloadSourceKind>[];
      final client = ModelCatalogHttpClient(
        sourcePolicy: policy,
        sourceFetch: (source) async {
          attempts.add(source.kind);
          if (source.kind == ModelDownloadSourceKind.mainlandMirror) {
            throw const ModelCatalogRequestException(
              ModelCatalogFailureKind.serviceUnavailable,
              debugDetails: 'mirror redirected to official',
            );
          }
          return Uint8List.fromList([1, 2, 3]);
        },
      );

      expect(
        await client.get(Uri.parse('https://huggingface.co/api/collections')),
        [1, 2, 3],
      );
      expect(attempts, [
        ModelDownloadSourceKind.mainlandMirror,
        ModelDownloadSourceKind.official,
      ]);

      attempts.clear();
      await client.get(Uri.parse('https://huggingface.co/api/models/test'));
      expect(attempts.first, ModelDownloadSourceKind.official);
    },
  );

  test('exposes a safe failure category instead of network details', () async {
    final policy = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'US',
    );
    final client = ModelCatalogHttpClient(
      sourcePolicy: policy,
      sourceFetch: (source) async => throw ModelCatalogRequestException(
        ModelCatalogFailureKind.timeout,
        debugDetails: 'SocketException: ${source.uri.host}:443',
      ),
    );

    await expectLater(
      client.get(Uri.parse('https://huggingface.co/api/collections')),
      throwsA(
        isA<ModelCatalogRequestException>()
            .having(
              (error) => error.kind,
              'kind',
              ModelCatalogFailureKind.timeout,
            )
            .having(
              (error) => error.toString(),
              'public string',
              isNot(contains('SocketException')),
            ),
      ),
    );
  });
}
