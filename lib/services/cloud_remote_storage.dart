import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/cloud_sync.dart';

abstract class CloudRemoteStorage {
  Future<void> testConnection();
  Future<Uint8List?> readBytes(String key);
  Future<void> uploadBytes(String key, List<int> bytes);
  Future<void> uploadFile(String key, File file, {String? sha256Digest});
  Future<void> downloadFile(String key, File destination, {int? expectedBytes});
  Future<void> delete(String key);
  void close();
}

class CloudRemoteStorageFactory {
  const CloudRemoteStorageFactory._();

  static CloudRemoteStorage create(CloudSyncSettings settings) {
    final problem = settings.configurationProblem;
    if (problem != null) throw StateError(problem);
    return switch (settings.provider) {
      CloudSyncProvider.webDav => WebDavRemoteStorage(settings.webDav),
      CloudSyncProvider.s3 => S3RemoteStorage(settings.s3),
    };
  }
}

class WebDavRemoteStorage implements CloudRemoteStorage {
  WebDavRemoteStorage(this.config, {HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 20);
  }

  final WebDavSyncConfig config;
  final HttpClient _client;

  Uri get _base => Uri.parse(config.serverUrl.trim());

  Map<String, String> get _headers => {
    HttpHeaders.authorizationHeader:
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
  };

  @override
  Future<void> testConnection() async {
    final result = await _send(
      'PROPFIND',
      _base,
      headers: {..._headers, 'Depth': '0'},
    );
    if (result.statusCode != 200 && result.statusCode != 207) {
      throw _httpError('WebDAV 连接失败', result);
    }
    await _ensureRemoteFolder();
    final probeKey =
        '.fknotes-connection-test-${DateTime.now().microsecondsSinceEpoch}';
    await uploadBytes(probeKey, utf8.encode('FKNotes'));
    final downloaded = await readBytes(probeKey);
    if (downloaded == null || utf8.decode(downloaded) != 'FKNotes') {
      throw const CloudStorageException('WebDAV 读写测试失败');
    }
    await delete(probeKey);
  }

  Future<void> _ensureRemoteFolder() async {
    final segments = _cleanSegments(config.remoteFolder);
    if (segments.isEmpty) return;
    final baseSegments = _base.pathSegments.where((part) => part.isNotEmpty);
    final current = <String>[...baseSegments];
    for (final segment in segments) {
      current.add(segment);
      final uri = _uriWithSegments(current);
      final result = await _send('MKCOL', uri, headers: _headers);
      if (result.statusCode != 201 &&
          result.statusCode != 200 &&
          result.statusCode != 204 &&
          result.statusCode != 405) {
        throw _httpError('无法创建 WebDAV 同步目录', result);
      }
    }
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final result = await _send('GET', _objectUri(key), headers: _headers);
    if (result.statusCode == 404) return null;
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('读取 WebDAV 数据失败', result);
    }
    return result.body;
  }

  @override
  Future<void> uploadBytes(String key, List<int> bytes) async {
    await _ensureRemoteFolder();
    final result = await _send(
      'PUT',
      _objectUri(key),
      headers: _headers,
      bodyBytes: bytes,
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('写入 WebDAV 数据失败', result);
    }
  }

  @override
  Future<void> uploadFile(String key, File file, {String? sha256Digest}) async {
    await _ensureRemoteFolder();
    final result = await _send(
      'PUT',
      _objectUri(key),
      headers: _headers,
      uploadFile: file,
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('上传 WebDAV 备份失败', result);
    }
  }

  @override
  Future<void> downloadFile(
    String key,
    File destination, {
    int? expectedBytes,
  }) async {
    final result = await _send(
      'GET',
      _objectUri(key),
      headers: _headers,
      downloadFile: destination,
      expectedDownloadBytes: expectedBytes,
    );
    if (result.statusCode == 404) {
      throw const CloudStorageException('云端备份文件不存在');
    }
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('下载 WebDAV 备份失败', result);
    }
  }

  @override
  Future<void> delete(String key) async {
    final result = await _send('DELETE', _objectUri(key), headers: _headers);
    if (result.statusCode != 404 &&
        (result.statusCode < 200 || result.statusCode >= 300)) {
      throw _httpError('删除 WebDAV 数据失败', result);
    }
  }

  Uri _objectUri(String key) => _uriWithSegments([
    ..._base.pathSegments.where((part) => part.isNotEmpty),
    ..._cleanSegments(config.remoteFolder),
    ..._cleanSegments(key),
  ]);

  Uri _uriWithSegments(List<String> segments) => Uri(
    scheme: _base.scheme,
    userInfo: _base.userInfo,
    host: _base.host,
    port: _base.hasPort ? _base.port : null,
    pathSegments: segments,
  );

  Future<_HttpResult> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? bodyBytes,
    File? uploadFile,
    File? downloadFile,
    int? expectedDownloadBytes,
  }) => _sendHttp(
    _client,
    method,
    uri,
    headers: headers,
    bodyBytes: bodyBytes,
    uploadFile: uploadFile,
    downloadFile: downloadFile,
    expectedDownloadBytes: expectedDownloadBytes,
  );

  @override
  void close() => _client.close(force: true);
}

class S3RemoteStorage implements CloudRemoteStorage {
  S3RemoteStorage(this.config, {HttpClient? client, DateTime Function()? clock})
    : _client = client ?? HttpClient(),
      _clock = clock ?? DateTime.now {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 20);
  }

  final S3SyncConfig config;
  final HttpClient _client;
  final DateTime Function() _clock;

  @override
  Future<void> testConnection() async {
    final probeKey =
        '.fknotes-connection-test-${_clock().toUtc().microsecondsSinceEpoch}';
    await uploadBytes(probeKey, utf8.encode('FKNotes'));
    final downloaded = await readBytes(probeKey);
    if (downloaded == null || utf8.decode(downloaded) != 'FKNotes') {
      throw const CloudStorageException('S3 读写测试失败');
    }
    await delete(probeKey);
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final result = await _signedSend('GET', _objectUri(key), _emptySha256);
    if (result.statusCode == 404) return null;
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('读取 S3 数据失败', result);
    }
    return result.body;
  }

  @override
  Future<void> uploadBytes(String key, List<int> bytes) async {
    final payloadHash = sha256.convert(bytes).toString();
    final result = await _signedSend(
      'PUT',
      _objectUri(key),
      payloadHash,
      bodyBytes: bytes,
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('写入 S3 数据失败', result);
    }
  }

  @override
  Future<void> uploadFile(String key, File file, {String? sha256Digest}) async {
    final payloadHash =
        sha256Digest ?? (await sha256.bind(file.openRead()).first).toString();
    final result = await _signedSend(
      'PUT',
      _objectUri(key),
      payloadHash,
      uploadFile: file,
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('上传 S3 备份失败', result);
    }
  }

  @override
  Future<void> downloadFile(
    String key,
    File destination, {
    int? expectedBytes,
  }) async {
    final result = await _signedSend(
      'GET',
      _objectUri(key),
      _emptySha256,
      downloadFile: destination,
      expectedDownloadBytes: expectedBytes,
    );
    if (result.statusCode == 404) {
      throw const CloudStorageException('云端备份文件不存在');
    }
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw _httpError('下载 S3 备份失败', result);
    }
  }

  @override
  Future<void> delete(String key) async {
    final result = await _signedSend('DELETE', _objectUri(key), _emptySha256);
    if (result.statusCode != 404 &&
        (result.statusCode < 200 || result.statusCode >= 300)) {
      throw _httpError('删除 S3 数据失败', result);
    }
  }

  Future<_HttpResult> _signedSend(
    String method,
    Uri uri,
    String payloadHash, {
    List<int>? bodyBytes,
    File? uploadFile,
    File? downloadFile,
    int? expectedDownloadBytes,
  }) {
    final now = _clock().toUtc();
    final date = _dateStamp(now);
    final amzDate = _amzDate(now);
    final host = _hostHeader(uri);
    final canonicalHeaders =
        'host:$host\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$amzDate\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
    final canonicalRequest = [
      method,
      _canonicalPath(uri),
      uri.query,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '$date/${config.region.trim()}/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final dateKey = _hmac(utf8.encode('AWS4${config.secretAccessKey}'), date);
    final regionKey = _hmac(dateKey, config.region.trim());
    final serviceKey = _hmac(regionKey, 's3');
    final signingKey = _hmac(serviceKey, 'aws4_request');
    final signature = _hex(_hmac(signingKey, stringToSign));
    final authorization =
        'AWS4-HMAC-SHA256 '
        'Credential=${config.accessKeyId.trim()}/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return _sendHttp(
      _client,
      method,
      uri,
      headers: {
        HttpHeaders.hostHeader: host,
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate,
        HttpHeaders.authorizationHeader: authorization,
      },
      bodyBytes: bodyBytes,
      uploadFile: uploadFile,
      downloadFile: downloadFile,
      expectedDownloadBytes: expectedDownloadBytes,
    );
  }

  Uri _objectUri(String key) => _bucketUri(
    objectSegments: [..._cleanSegments(config.prefix), ..._cleanSegments(key)],
  );

  Uri _bucketUri({
    List<String> objectSegments = const [],
    Map<String, String> query = const {},
  }) {
    final endpoint = Uri.parse(config.endpoint.trim());
    final pathSegments = <String>[
      ...endpoint.pathSegments.where((part) => part.isNotEmpty),
      if (config.pathStyle) config.bucket.trim(),
      ...objectSegments,
    ];
    final host = config.pathStyle
        ? endpoint.host
        : '${config.bucket.trim()}.${endpoint.host}';
    final canonicalQuery = _canonicalQuery(query);
    return Uri(
      scheme: endpoint.scheme,
      host: host,
      port: endpoint.hasPort ? endpoint.port : null,
      pathSegments: pathSegments,
      query: canonicalQuery.isEmpty ? null : canonicalQuery,
    );
  }

  @override
  void close() => _client.close(force: true);

  static const _emptySha256 =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
}

class CloudStorageException implements Exception {
  final String message;
  final int? statusCode;

  const CloudStorageException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class _HttpResult {
  final int statusCode;
  final Uint8List body;

  const _HttpResult(this.statusCode, this.body);
}

Future<_HttpResult> _sendHttp(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  List<int>? bodyBytes,
  File? uploadFile,
  File? downloadFile,
  int? expectedDownloadBytes,
}) async {
  if (bodyBytes != null && uploadFile != null) {
    throw ArgumentError('不能同时发送内存数据和文件');
  }
  final request = await client
      .openUrl(method, uri)
      .timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('连接云端超时'),
      );
  request.followRedirects = false;
  headers.forEach(request.headers.set);
  if (bodyBytes != null) {
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
  } else if (uploadFile != null) {
    request.contentLength = await uploadFile.length();
    await request.addStream(uploadFile.openRead());
  }
  final response = await request.close().timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('等待云端响应超时'),
  );
  final successful = response.statusCode >= 200 && response.statusCode < 300;
  if (downloadFile != null && successful) {
    if (expectedDownloadBytes != null &&
        response.contentLength >= 0 &&
        response.contentLength != expectedDownloadBytes) {
      await response.drain<void>();
      throw const CloudStorageException('云端文件长度与同步清单不一致');
    }
    await downloadFile.parent.create(recursive: true);
    final temporary = File('${downloadFile.path}.part');
    if (await temporary.exists()) await temporary.delete();
    try {
      final output = temporary.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (expectedDownloadBytes != null &&
              received > expectedDownloadBytes) {
            throw const CloudStorageException('云端文件超过同步清单声明的大小');
          }
          output.add(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (expectedDownloadBytes != null && received != expectedDownloadBytes) {
        throw const CloudStorageException('云端文件长度与同步清单不一致');
      }
      if (await downloadFile.exists()) await downloadFile.delete();
      await temporary.rename(downloadFile.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return _HttpResult(response.statusCode, Uint8List(0));
  }
  final builder = BytesBuilder(copy: false);
  var size = 0;
  await for (final chunk in response) {
    size += chunk.length;
    if (size > 1024 * 1024) {
      throw const CloudStorageException('云端响应异常：内容过大');
    }
    builder.add(chunk);
  }
  return _HttpResult(response.statusCode, builder.takeBytes());
}

CloudStorageException _httpError(String prefix, _HttpResult result) {
  final detail = utf8.decode(result.body, allowMalformed: true).trim();
  final compact = detail.replaceAll(RegExp(r'\s+'), ' ');
  return CloudStorageException(
    compact.isEmpty
        ? '$prefix（HTTP ${result.statusCode}）'
        : '$prefix（HTTP ${result.statusCode}）：${compact.substring(0, compact.length.clamp(0, 240))}',
    statusCode: result.statusCode,
  );
}

List<String> _cleanSegments(String value) => value
    .trim()
    .replaceAll('\\', '/')
    .split('/')
    .where((part) => part.isNotEmpty)
    .toList(growable: false);

String _hostHeader(Uri uri) {
  final defaultPort =
      (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
  return defaultPort ? uri.host : '${uri.host}:${uri.port}';
}

String _canonicalPath(Uri uri) =>
    '/${uri.pathSegments.map(_awsEncode).join('/')}';

String _canonicalQuery(Map<String, String> values) {
  final entries =
      values.entries
          .map(
            (entry) => MapEntry(_awsEncode(entry.key), _awsEncode(entry.value)),
          )
          .toList()
        ..sort((left, right) {
          final key = left.key.compareTo(right.key);
          return key == 0 ? left.value.compareTo(right.value) : key;
        });
  return entries.map((entry) => '${entry.key}=${entry.value}').join('&');
}

String _awsEncode(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2d ||
        byte == 0x2e ||
        byte == 0x5f ||
        byte == 0x7e;
    if (unreserved) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return buffer.toString();
}

String _dateStamp(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}'
    '${value.month.toString().padLeft(2, '0')}'
    '${value.day.toString().padLeft(2, '0')}';

String _amzDate(DateTime value) =>
    '${_dateStamp(value)}T'
    '${value.hour.toString().padLeft(2, '0')}'
    '${value.minute.toString().padLeft(2, '0')}'
    '${value.second.toString().padLeft(2, '0')}Z';

List<int> _hmac(List<int> key, String value) =>
    Hmac(sha256, key).convert(utf8.encode(value)).bytes;

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
