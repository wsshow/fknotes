import 'dart:async';
import 'dart:io';

import 'package:fknotes/services/model_download_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fknotes_model_transport_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('falls back to the next source and reports the active node', () async {
    final payload = [1, 2, 3, 4, 5];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/primary') {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.add(payload);
      }
      await request.response.close();
    });
    final labels = <String>[];
    final destination = File(p.join(temporaryDirectory.path, 'model.part'));

    final selected = await ModelDownloadTransport().download(
      sources: [
        ModelDownloadSource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/primary'),
          label: '国内镜像',
        ),
        ModelDownloadSource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/fallback'),
          label: '官方源',
        ),
      ],
      partial: destination,
      expectedBytes: payload.length,
      userAgent: 'fknotes/test',
      onProgress: (event) => labels.add(event.sourceLabel),
    );

    expect(selected, '官方源');
    expect(labels, containsAllInOrder(['国内镜像', '官方源']));
    expect(await destination.readAsBytes(), payload);
  });

  test('actively cancels while waiting for response headers', () async {
    final requestReceived = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      requestReceived.complete();
      await releaseResponse.future;
      try {
        request.response.add([1]);
        await request.response.close();
      } on HttpException {
        // The client intentionally closed the connection.
      }
    });
    var canceled = false;
    final destination = File(p.join(temporaryDirectory.path, 'model.part'));
    final transport = ModelDownloadTransport(
      cancellationPollInterval: const Duration(milliseconds: 5),
      responseTimeout: const Duration(seconds: 5),
    );
    final stopwatch = Stopwatch()..start();

    final download = transport.download(
      sources: [
        ModelDownloadSource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/model'),
          label: '测试节点',
        ),
      ],
      partial: destination,
      expectedBytes: 1,
      userAgent: 'fknotes/test',
      shouldCancel: () => canceled,
      onProgress: (_) {},
    );
    await requestReceived.future;
    canceled = true;

    await expectLater(download, throwsA(isA<ModelDownloadCanceled>()));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('keeps resumable bytes when an active transfer is canceled', () async {
    final requestReceived = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      requestReceived.complete();
      await releaseResponse.future;
      try {
        request.response.add([4, 5, 6]);
        await request.response.close();
      } on HttpException {
        // The client intentionally closed the connection.
      }
    });
    var canceled = false;
    final destination = File(p.join(temporaryDirectory.path, 'model.part'));
    await destination.writeAsBytes([1, 2, 3]);
    final transport = ModelDownloadTransport(
      cancellationPollInterval: const Duration(milliseconds: 5),
    );

    final download = transport.download(
      sources: [
        ModelDownloadSource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/model'),
          label: '测试节点',
        ),
      ],
      partial: destination,
      expectedBytes: 6,
      userAgent: 'fknotes/test',
      shouldCancel: () => canceled,
      onProgress: (_) {},
    );
    await requestReceived.future;
    canceled = true;

    await expectLater(download, throwsA(isA<ModelDownloadCanceled>()));

    expect(await destination.readAsBytes(), [1, 2, 3]);
  });
}
