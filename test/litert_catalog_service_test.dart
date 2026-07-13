import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/models/litert_model.dart';
import 'package:fknotes/services/litert_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('fknotes_litert_catalog_');
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  test(
    'bundled snapshot is discoverable but is not managed automatically',
    () async {
      final service = LiteRtCatalogService(cacheDirectory: cache.path);

      await service.loadCache();

      expect(service.entries, isNotEmpty);
      expect(
        service.entries.map((entry) => entry.repository),
        contains('litert-community/Qwen3-0.6B'),
      );
      expect(service.cachedDetails, isNotEmpty);
      expect(service.managedDetails, isEmpty);
    },
  );

  test(
    'catalog only keeps supported public LiteRT-LM model candidates',
    () async {
      final service = LiteRtCatalogService(
        cacheDirectory: cache.path,
        httpGet: (_) async => _jsonBytes([
          {
            'title': 'Qwen Family',
            'items': [
              _collectionModel('litert-community/Qwen3-4B'),
              _collectionModel(
                'litert-community/Qwen3-Restricted',
                gated: 'manual',
              ),
              _collectionModel('other/Qwen3-4B'),
              _collectionModel('litert-community/EmbeddingGemma'),
            ],
          },
          {
            'title': 'Unsupported Experiments',
            'items': [_collectionModel('litert-community/Experimental-1B')],
          },
        ]),
      );

      final entries = await service.sync();

      expect(entries, hasLength(1));
      expect(entries.single.repository, 'litert-community/Qwen3-4B');
    },
  );

  test(
    'inspection pins a generic verified file and persists explicit add',
    () async {
      final service = LiteRtCatalogService(
        cacheDirectory: cache.path,
        httpGet: (_) async => _jsonBytes({
          'author': 'litert-community',
          'private': false,
          'gated': false,
          'disabled': false,
          'library_name': 'litert-lm',
          'sha': _repeat('a', 40),
          'cardData': {
            'license': 'apache-2.0',
            'language': ['zh', 'en'],
          },
          'siblings': [
            _modelFile('qwen-web.litertlm', 200, _repeat('1', 64)),
            _modelFile('qwen.qualcomm.int4.litertlm', 300, _repeat('2', 64)),
            _modelFile('qwen_f32.litertlm', 500, _repeat('3', 64)),
            _modelFile('qwen_mixed_int4.litertlm', 400, _repeat('4', 64)),
          ],
        }),
      );
      const entry = LiteRtCatalogEntry(
        repository: 'litert-community/Qwen3-Test',
        collection: 'Qwen Family',
      );

      final spec = await service.inspect(entry);
      await service.markAdded(entry.repository);

      expect(spec.file.name, 'qwen_mixed_int4.litertlm');
      expect(spec.file.sha256, _repeat('4', 64));
      expect(spec.revision, _repeat('a', 40));
      expect(service.managedDetails.single.repository, entry.repository);

      final restored = LiteRtCatalogService(cacheDirectory: cache.path);
      await restored.loadCache();
      expect(restored.managedDetails.single.repository, entry.repository);
    },
  );

  test(
    'inspection rejects files without a verified generic Android package',
    () {
      final service = LiteRtCatalogService(
        cacheDirectory: cache.path,
        httpGet: (_) async => _jsonBytes({
          'author': 'litert-community',
          'private': false,
          'gated': false,
          'disabled': false,
          'library_name': 'litert-lm',
          'sha': _repeat('a', 40),
          'siblings': [_modelFile('only-web.litertlm', 200, _repeat('1', 64))],
        }),
      );

      expect(
        service.inspect(
          const LiteRtCatalogEntry(
            repository: 'litert-community/Unsupported-Web-Model',
            collection: 'Qwen Family',
          ),
        ),
        throwsA(isA<LiteRtCatalogException>()),
      );
    },
  );
}

Map<String, Object?> _collectionModel(
  String repository, {
  Object gated = false,
}) => {
  'type': 'model',
  'id': repository,
  'private': false,
  'gated': gated,
  'pipeline_tag': 'text-generation',
};

Map<String, Object?> _modelFile(String name, int size, String checksum) => {
  'rfilename': name,
  'size': size,
  'lfs': {'sha256': checksum, 'size': size},
};

Uint8List _jsonBytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

String _repeat(String value, int count) => List.filled(count, value).join();
