import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/models/taobao_mnn_model.dart';
import 'package:fknotes/services/taobao_mnn_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('fknotes_mnn_catalog_');
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  test(
    'sync keeps public taobao-mnn chat models and caches the result',
    () async {
      final service = TaobaoMnnCatalogService(
        cacheDirectory: cache.path,
        httpGet: (uri) async => _jsonBytes([
          {
            'title': 'Qwen3-MNN',
            'items': [
              {
                'type': 'model',
                'id': 'taobao-mnn/Qwen3-0.6B-MNN',
                'author': 'taobao-mnn',
                'private': false,
                'gated': false,
                'pipeline_tag': 'text-generation',
                'downloads': 128,
                'lastModified': '2026-07-12T10:00:00.000Z',
              },
              {
                'type': 'model',
                'id': 'someone/Not-Trusted-MNN',
                'author': 'someone',
                'private': false,
                'gated': false,
                'pipeline_tag': 'text-generation',
              },
            ],
          },
          {
            'title': 'Embedding-MNN',
            'items': [
              {
                'type': 'model',
                'id': 'taobao-mnn/Qwen3-Embedding-0.6B-MNN',
                'author': 'taobao-mnn',
                'private': false,
                'gated': false,
                'pipeline_tag': 'text-generation',
              },
            ],
          },
        ]),
      );

      final entries = await service.sync();
      expect(entries, hasLength(1));
      expect(entries.single.repository, 'taobao-mnn/Qwen3-0.6B-MNN');
      expect(entries.single.collection, 'Qwen3-MNN');

      final restored = TaobaoMnnCatalogService(cacheDirectory: cache.path);
      await restored.loadCache();
      expect(restored.entries.single.repository, entries.single.repository);
      expect(restored.lastSyncedAt, isNotNull);
    },
  );

  test(
    'inspect pins revision, validates files and persists capabilities',
    () async {
      final entry = TaobaoMnnCatalogEntry(
        repository: 'taobao-mnn/Qwen-VL-Test-MNN',
        collection: 'Qwen-VL-MNN',
      );
      final service = TaobaoMnnCatalogService(
        cacheDirectory: cache.path,
        httpGet: (uri) async {
          if (uri.path.startsWith('/api/models/')) {
            return _jsonBytes({
              'author': 'taobao-mnn',
              'private': false,
              'gated': false,
              'disabled': false,
              'sha': '1234567890abcdef1234567890abcdef12345678',
              'cardData': {
                'license': 'apache-2.0',
                'language': ['zh', 'en'],
                'tags': ['chat'],
              },
              'siblings': [
                _file('config.json', 120, blobId: _repeat('a', 40)),
                _file('llm_config.json', 240, blobId: _repeat('b', 40)),
                _file('llm.mnn', 1024, sha256: _repeat('c', 64)),
                _file(
                  'llm.mnn.weight',
                  2 * 1024 * 1024,
                  sha256: _repeat('d', 64),
                ),
                _file('tokenizer.txt', 2048, blobId: _repeat('e', 40)),
                _file('visual.mnn', 512, sha256: _repeat('f', 64)),
                _file('visual.mnn.weight', 4096, sha256: _repeat('1', 64)),
                _file('../unsafe.bin', 1, sha256: _repeat('2', 64)),
              ],
            });
          }
          if (uri.path.endsWith('/config.json')) {
            return _jsonBytes({
              'llm_model': 'llm.mnn',
              'llm_weight': 'llm.mnn.weight',
              'temperature': .8,
              'topP': .9,
              'topK': 30,
            });
          }
          if (uri.path.endsWith('/llm_config.json')) {
            return _jsonBytes({
              'is_visual': true,
              'max_position_embeddings': 65536,
              'jinja': {'chat_template': '<tool_call>'},
            });
          }
          throw StateError('Unexpected URI: $uri');
        },
      );

      final spec = await service.inspect(entry);
      expect(spec.revision, '1234567890abcdef1234567890abcdef12345678');
      expect(spec.capabilities.imageInput, isTrue);
      expect(spec.capabilities.toolCalling, isTrue);
      expect(spec.nativeContextTokens, 65536);
      expect(spec.generationOptions.temperature, .8);
      expect(spec.files.any((file) => file.name.contains('..')), isFalse);

      final restored = TaobaoMnnCatalogService(cacheDirectory: cache.path);
      await restored.loadCache();
      expect(restored.cachedSpec(entry.repository)?.revision, spec.revision);
      expect(
        restored.cachedSpec(entry.repository)?.capabilities.imageInput,
        isTrue,
      );
    },
  );

  test('inspect rejects a repository without a complete MNN runtime', () async {
    final service = TaobaoMnnCatalogService(
      cacheDirectory: cache.path,
      httpGet: (uri) async => _jsonBytes({
        'author': 'taobao-mnn',
        'private': false,
        'gated': false,
        'disabled': false,
        'sha': '1234567890abcdef1234567890abcdef12345678',
        'siblings': [
          _file('config.json', 10, blobId: _repeat('a', 40)),
          _file('model.safetensors', 100, sha256: _repeat('b', 64)),
        ],
      }),
    );

    await expectLater(
      service.inspect(
        const TaobaoMnnCatalogEntry(
          repository: 'taobao-mnn/Incomplete-MNN',
          collection: 'Test-MNN',
        ),
      ),
      throwsA(isA<TaobaoMnnCatalogException>()),
    );
  });

  test('inspect rejects files that cannot be integrity-checked', () async {
    final service = TaobaoMnnCatalogService(
      cacheDirectory: cache.path,
      httpGet: (uri) async => _jsonBytes({
        'author': 'taobao-mnn',
        'private': false,
        'gated': false,
        'disabled': false,
        'sha': '1234567890abcdef1234567890abcdef12345678',
        'siblings': [
          _file('config.json', 10),
          _file('llm_config.json', 10, blobId: _repeat('a', 40)),
          _file('llm.mnn', 10, sha256: _repeat('b', 64)),
          _file('llm.mnn.weight', 10, sha256: _repeat('c', 64)),
          _file('tokenizer.txt', 10, blobId: _repeat('d', 40)),
        ],
      }),
    );

    await expectLater(
      service.inspect(
        const TaobaoMnnCatalogEntry(
          repository: 'taobao-mnn/Unverifiable-MNN',
          collection: 'Test-MNN',
        ),
      ),
      throwsA(
        isA<TaobaoMnnCatalogException>().having(
          (error) => error.message,
          'message',
          contains('verification metadata'),
        ),
      ),
    );
  });
}

Map<String, Object?> _file(
  String name,
  int size, {
  String? sha256,
  String? blobId,
}) => {
  'rfilename': name,
  'size': size,
  'blobId': blobId,
  if (sha256 != null) 'lfs': {'sha256': sha256, 'size': size},
};

Uint8List _jsonBytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

String _repeat(String value, int count) => List.filled(count, value).join();
