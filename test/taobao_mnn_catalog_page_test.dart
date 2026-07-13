import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/models/taobao_mnn_model.dart';
import 'package:fknotes/models/litert_model.dart';
import 'package:fknotes/pages/taobao_mnn_catalog_page.dart';
import 'package:fknotes/services/litert_catalog_service.dart';
import 'package:fknotes/services/taobao_mnn_catalog_service.dart';
import 'package:fknotes/services/model_catalog_http_client.dart';
import 'package:fknotes/services/model_download_source_policy.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'catalog opens details before user validates and adds MNN model',
    (tester) async {
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
      final verifiedModel = await tester.runAsync(
        () => service.inspect(service.entries.single),
      );
      final pageService = _ManualVerificationTaobaoService(
        service.entries.single,
        verifiedModel!,
      );
      final sourcePolicy = ModelDownloadSourcePolicy(
        settingsPath: p.join(cache.path, 'source.json'),
      );
      await tester.runAsync(sourcePolicy.load);

      await tester.pumpWidget(
        MaterialApp(
          home: TaobaoMnnCatalogPage(
            service: pageService,
            sourcePolicy: sourcePolicy,
            curatedRepositories: const {},
            onInstall: (model) async => installed = model,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Qwen3-VL-Test'), findsOneWidget);
      expect(find.text('42 次下载'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('taobao-mnn-search')),
        'not-found',
      );
      await tester.pump();
      expect(find.text('没有匹配的本地模型'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('taobao-mnn-search')),
        'qwen',
      );
      await tester.pump();

      await tester.tap(find.text('Qwen3-VL-Test'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('模型包尚未校验'), findsOneWidget);
      expect(find.text('MNN 文件与运行配置检查通过'), findsNothing);
      expect(find.byKey(const Key('add-taobao-mnn-model')), findsNothing);
      expect(pageService.inspectCalls, 0);

      await tester.tap(find.byKey(const Key('verify-taobao-mnn-model')));
      await tester.pump();
      await tester.pump();
      expect(pageService.inspectCalls, 1);
      expect(find.text('MNN 文件与运行配置检查通过'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-taobao-mnn-model')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('图片输入'), findsOneWidget);
      expect(find.text('apache-2.0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-taobao-mnn-model')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(installed?.repository, 'taobao-mnn/Qwen3-VL-Test-MNN');
      expect(installed?.capabilities.imageInput, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog timeout hides raw network exception details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fknotes_catalog_timeout_'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        if (await cache.exists()) await cache.delete(recursive: true);
      }),
    );
    final service = TaobaoMnnCatalogService(
      cacheDirectory: cache.path,
      httpGet: (uri) async => throw const ModelCatalogRequestException(
        ModelCatalogFailureKind.timeout,
        debugDetails:
            'SocketException: connection timed out, host: huggingface.co:443',
      ),
    );
    await tester.runAsync(service.loadCache);
    final sourcePolicy = ModelDownloadSourcePolicy(
      settingsPath: p.join(cache.path, 'source.json'),
    );
    await tester.runAsync(sourcePolicy.load);

    await tester.pumpWidget(
      MaterialApp(
        home: TaobaoMnnCatalogPage(
          service: service,
          sourcePolicy: sourcePolicy,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('模型目录刷新超时'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('huggingface.co'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('切换网络源'), findsOneWidget);
  });

  testWidgets(
    'unified catalog shows cached LiteRT verification without network',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);
      final cache = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fknotes_litert_catalog_page_'),
      ))!;
      addTearDown(
        () => tester.runAsync(() async {
          if (await cache.exists()) await cache.delete(recursive: true);
        }),
      );
      final mnnService = TaobaoMnnCatalogService(
        cacheDirectory: p.join(cache.path, 'mnn'),
      );
      final liteRtService = LiteRtCatalogService(
        cacheDirectory: p.join(cache.path, 'litert'),
      );
      LiteRtModelSpec? installed;
      await tester.runAsync(() async {
        await mnnService.loadCache();
        await liteRtService.loadCache();
      });
      final sourcePolicy = ModelDownloadSourcePolicy(
        settingsPath: p.join(cache.path, 'source.json'),
      );
      await tester.runAsync(sourcePolicy.load);

      await tester.pumpWidget(
        MaterialApp(
          home: TaobaoMnnCatalogPage(
            service: mnnService,
            liteRtService: liteRtService,
            includeLiteRt: true,
            curatedRepositories: const {},
            sourcePolicy: sourcePolicy,
            onInstallLiteRt: (model) async => installed = model,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Qwen3-0.6B'), findsOneWidget);
      expect(find.text('LiteRT-LM'), findsWidgets);

      await tester.tap(find.text('Qwen3-0.6B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('LiteRT-LM 文件'), findsOneWidget);
      expect(find.text('qwen3_0_6b_mixed_int4.litertlm'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('add-litert-model')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('重新校验模型包'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-litert-model')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(installed?.repository, 'litert-community/Qwen3-0.6B');
      expect(tester.takeException(), isNull);
    },
  );
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

class _ManualVerificationTaobaoService extends TaobaoMnnCatalogService {
  final TaobaoMnnCatalogEntry entry;
  final TaobaoMnnModelSpec verifiedModel;
  TaobaoMnnModelSpec? _cached;
  int inspectCalls = 0;

  _ManualVerificationTaobaoService(this.entry, this.verifiedModel)
    : super(cacheDirectory: Directory.systemTemp.path);

  @override
  List<TaobaoMnnCatalogEntry> get entries => [entry];

  @override
  Future<void> loadCache() async {}

  @override
  Future<List<TaobaoMnnCatalogEntry>> sync() async => entries;

  @override
  TaobaoMnnModelSpec? cachedSpec(String repository) => _cached;

  @override
  Future<TaobaoMnnModelSpec> inspect(
    TaobaoMnnCatalogEntry entry, {
    bool force = false,
  }) async {
    inspectCalls++;
    _cached = verifiedModel;
    return verifiedModel;
  }
}
