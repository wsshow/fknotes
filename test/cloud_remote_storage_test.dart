import 'dart:convert';
import 'dart:io';

import 'package:fknotes/models/cloud_sync.dart';
import 'package:fknotes/services/cloud_remote_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Map<String, List<int>> objects;
  late List<HttpRequest> requests;

  setUp(() async {
    objects = {};
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'WebDAV connection test verifies authenticated read and write',
    () async {
      server.listen((request) async {
        requests.add(request);
        final body = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        switch (request.method) {
          case 'PROPFIND':
            request.response.statusCode = 207;
          case 'MKCOL':
            request.response.statusCode = 201;
          case 'PUT':
            objects[request.uri.path] = body;
            request.response.statusCode = 201;
          case 'GET':
            final value = objects[request.uri.path];
            if (value == null) {
              request.response.statusCode = 404;
            } else {
              request.response.add(value);
            }
          case 'DELETE':
            objects.remove(request.uri.path);
            request.response.statusCode = 204;
        }
        await request.response.close();
      });
      final storage = WebDavRemoteStorage(
        WebDavSyncConfig(
          serverUrl: 'http://${server.address.host}:${server.port}/dav',
          username: 'alice',
          password: 'secret',
          remoteFolder: 'FKNotes',
        ),
      );
      final temporary = await Directory.systemTemp.createTemp(
        'webdav-transfer',
      );

      try {
        await storage.testConnection();
        final source = File('${temporary.path}/source.zip');
        final downloaded = File('${temporary.path}/downloaded.zip');
        await source.writeAsBytes([1, 2, 3, 4]);
        await storage.uploadFile('snapshot.zip', source);
        await storage.downloadFile(
          'snapshot.zip',
          downloaded,
          expectedBytes: 4,
        );
        expect(await downloaded.readAsBytes(), [1, 2, 3, 4]);
        await storage.delete('snapshot.zip');
      } finally {
        storage.close();
        await temporary.delete(recursive: true);
      }

      expect(objects, isEmpty);
      expect(
        requests.first.headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('alice:secret'))}',
      );
      expect(
        requests.map((request) => request.uri.path),
        contains(startsWith('/dav/FKNotes/.fknotes-connection-test-')),
      );
    },
  );

  test('S3 connection test signs path-style object requests', () async {
    server.listen((request) async {
      requests.add(request);
      final body = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      switch (request.method) {
        case 'PUT':
          objects[request.uri.path] = body;
        case 'GET':
          final value = objects[request.uri.path];
          if (value == null) {
            request.response.statusCode = 404;
          } else {
            request.response.add(value);
          }
        case 'DELETE':
          objects.remove(request.uri.path);
          request.response.statusCode = 204;
      }
      await request.response.close();
    });
    final storage = S3RemoteStorage(
      S3SyncConfig(
        endpoint: 'http://${server.address.host}:${server.port}',
        region: 'us-east-1',
        bucket: 'notes',
        accessKeyId: 'AKID',
        secretAccessKey: 'SECRET',
        prefix: 'FKNotes',
      ),
      clock: () => DateTime.utc(2026, 7, 12, 8, 30),
    );

    try {
      await storage.testConnection();
    } finally {
      storage.close();
    }

    expect(objects, isEmpty);
    expect(
      requests.first.uri.path,
      startsWith('/notes/FKNotes/.fknotes-connection-test-'),
    );
    for (final request in requests) {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        startsWith('AWS4-HMAC-SHA256 Credential=AKID/20260712/us-east-1/s3/'),
      );
      expect(request.headers.value('x-amz-date'), '20260712T083000Z');
    }
    expect(
      requests.map((request) => request.uri.path),
      contains(startsWith('/notes/FKNotes/.fknotes-connection-test-')),
    );
  });
}
