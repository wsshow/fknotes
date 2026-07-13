import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/models/taobao_mnn_model.dart';
import 'package:fknotes/pages/taobao_mnn_catalog_page.dart';
import 'package:fknotes/services/taobao_mnn_catalog_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog searches, validates and adds an official MNN model', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fknotes_mnn_catalog_page_'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        if (await cache.exists()) await cache.delete(recursive: true);
      }),
    );
    TaobaoMnnModelSpec? installed;
    final service = TaobaoMnnCatalogService(
      cacheDirectory: cache.path,
      httpGet: (uri) async {
        if (uri.path == '/api/collections') {
          return _jsonBytes([
            {
              'title': 'Qwen3-VL-MNN',
              'items': [
                {
                  'type': 'model',
                  'id': 'taobao-mnn/Qwen3-VL-Test-MNN',
                  'author': 'taobao-mnn',
                  'private': false,
                  'gated': false,
                  'pipeline_tag': 'text-generation',
                  'downloads': 42,
                },
              ],
            },
          ]);
        }
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
              _file('config.json', 100, blobId: _repeat('a', 40)),
              _file('llm_config.json', 200, blobId: _repeat('b', 40)),
              _file('llm.mnn', 1024, sha256: _repeat('c', 64)),
              _file(
                'llm.mnn.weight',
                512 * 1024 * 1024,
                sha256: _repeat('d', 64),
              ),
              _file('tokenizer.txt', 2048, blobId: _repeat('e', 40)),
              _file('visual.mnn', 512, sha256: _repeat('f', 64)),
              _file('visual.mnn.weight', 1024, sha256: _repeat('1', 64)),
            ],
          });
        }
        if (uri.path.endsWith('/llm_config.json')) {
          return _jsonBytes({'is_visual': true});
        }
        if (uri.path.endsWith('/config.json')) {
          return _jsonBytes({
            'llm_model': 'llm.mnn',
            'llm_weight': 'llm.mnn.weight',
          });
        }
        throw StateError('Unexpected URI: $uri');
      },
    );
    await tester.runAsync(service.sync);
    await tester.runAsync(() => service.inspect(service.entries.single));

    await tester.pumpWidget(
      MaterialApp(
        home: TaobaoMnnCatalogPage(
          service: service,
          curatedRepositories: const {},
          onInstall: (model) async => installed = model,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Qwen3-VL-Test'), findsOneWidget);
    expect(find.text('42 次下载'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('taobao-mnn-search')),
      'not-found',
    );
    await tester.pump();
    expect(find.text('没有匹配的 MNN 模型'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('taobao-mnn-search')), 'qwen');
    await tester.pump();

    await tester.tap(find.text('Qwen3-VL-Test'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MNN 文件与运行配置检查通过'), findsOneWidget);
    expect(find.text('图片输入'), findsOneWidget);
    expect(find.text('apache-2.0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-taobao-mnn-model')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(installed?.repository, 'taobao-mnn/Qwen3-VL-Test-MNN');
    expect(installed?.capabilities.imageInput, isTrue);
    expect(tester.takeException(), isNull);
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
