import 'dart:io';

import 'package:fknotes/services/model_download_source_policy.dart';
import 'package:fknotes/services/model_download_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late String settingsPath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fknotes_download_source_policy_',
    );
    settingsPath = p.join(temporaryDirectory.path, 'download.json');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  List<ModelDownloadSource> sources() => [
    ModelDownloadSource(
      uri: Uri.parse('https://huggingface.co/model'),
      label: 'Hugging Face',
      kind: ModelDownloadSourceKind.official,
    ),
    ModelDownloadSource(
      uri: Uri.parse('https://hf-mirror.com/model'),
      label: '国内镜像',
      kind: ModelDownloadSourceKind.mainlandMirror,
    ),
    ModelDownloadSource(
      uri: Uri.parse('https://github.com/model'),
      label: 'GitHub',
    ),
  ];

  test('automatic ordering uses region only as the initial hint', () {
    final mainland = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'CN',
    );
    final global = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'US',
    );

    expect(mainland.order(sources()).first.label, '国内镜像');
    expect(global.order(sources()).first.label, 'Hugging Face');

    global.reportSuccessfulSource(sources()[1]);
    expect(global.order(sources()).first.label, '国内镜像');
  });

  test('manual preference persists and always keeps a fallback', () async {
    final policy = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'CN',
    );
    await policy.setPreference(ModelDownloadSourcePreference.officialFirst);

    final restored = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'CN',
    );
    await restored.load();
    final ordered = restored.order(sources());

    expect(restored.preference, ModelDownloadSourcePreference.officialFirst);
    expect(ordered.map((source) => source.label), [
      'Hugging Face',
      '国内镜像',
      'GitHub',
    ]);
  });

  test('automatic mode persists a recently healthy endpoint', () async {
    final policy = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'CN',
    );
    policy.reportSuccessfulSource(sources().first);
    await policy.flush();

    final restored = ModelDownloadSourcePolicy(
      settingsPath: settingsPath,
      countryCodeProvider: () => 'CN',
    );
    await restored.load();

    expect(restored.order(sources()).first.label, 'Hugging Face');
  });
}
