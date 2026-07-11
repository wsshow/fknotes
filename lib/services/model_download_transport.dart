import 'dart:async';
import 'dart:io';

class ModelDownloadCanceled implements Exception {
  const ModelDownloadCanceled();
}

class ModelDownloadSource {
  final Uri uri;
  final String label;

  const ModelDownloadSource({required this.uri, required this.label});
}

class ModelDownloadEvent {
  final int transferredBytes;
  final bool connecting;
  final String sourceLabel;

  const ModelDownloadEvent({
    required this.transferredBytes,
    required this.connecting,
    required this.sourceLabel,
  });
}

/// Downloads one model file with resume, source fallback and active cancellation.
///
/// Integrity remains the responsibility of the model service because it owns
/// the pinned hash. A source is therefore only accepted after the service's
/// existing size and SHA-256 checks pass.
class ModelDownloadTransport {
  ModelDownloadTransport({
    HttpClient Function()? clientFactory,
    this.cancellationPollInterval = const Duration(milliseconds: 100),
    this.responseTimeout = const Duration(seconds: 25),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  static final instance = ModelDownloadTransport();

  final HttpClient Function() _clientFactory;
  final Duration cancellationPollInterval;
  final Duration responseTimeout;
  final Duration idleTimeout;

  Future<String> download({
    required List<ModelDownloadSource> sources,
    required File partial,
    required int expectedBytes,
    required String userAgent,
    required void Function(ModelDownloadEvent event) onProgress,
    bool Function()? shouldCancel,
  }) async {
    if (sources.isEmpty) throw ArgumentError.value(sources, 'sources');
    Object? lastError;
    for (final source in sources) {
      try {
        await _downloadFromSource(
          source: source,
          partial: partial,
          expectedBytes: expectedBytes,
          userAgent: userAgent,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
        return source.label;
      } on ModelDownloadCanceled {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const HttpException('没有可用的模型下载源');
  }

  Future<void> _downloadFromSource({
    required ModelDownloadSource source,
    required File partial,
    required int expectedBytes,
    required String userAgent,
    required void Function(ModelDownloadEvent event) onProgress,
    bool Function()? shouldCancel,
  }) async {
    var existing = await partial.exists() ? await partial.length() : 0;
    if (existing > expectedBytes) {
      await partial.delete();
      existing = 0;
    }
    if (existing == expectedBytes) {
      onProgress(
        ModelDownloadEvent(
          transferredBytes: existing,
          connecting: false,
          sourceLabel: source.label,
        ),
      );
      return;
    }
    if (shouldCancel?.call() == true) throw const ModelDownloadCanceled();

    onProgress(
      ModelDownloadEvent(
        transferredBytes: existing,
        connecting: true,
        sourceLabel: source.label,
      ),
    );

    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    HttpClientRequest? request;
    RandomAccessFile? output;
    var canceled = false;
    final cancellationTimer = shouldCancel == null
        ? null
        : Timer.periodic(cancellationPollInterval, (_) {
            if (canceled || shouldCancel() != true) return;
            canceled = true;
            request?.abort(const ModelDownloadCanceled());
            client.close(force: true);
          });
    try {
      request = await client.getUrl(source.uri).timeout(responseTimeout);
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(responseTimeout);
      final canResume = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !canResume) {
        throw HttpException(
          '${source.label} 下载失败（${response.statusCode}）',
          uri: source.uri,
        );
      }
      if (existing > 0 && !canResume) {
        await partial.delete();
        existing = 0;
      }
      output = await partial.open(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      var received = existing;
      await for (final chunk in response.timeout(idleTimeout)) {
        if (shouldCancel?.call() == true) {
          throw const ModelDownloadCanceled();
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        if (received > expectedBytes) {
          throw const FormatException('模型下载大小异常');
        }
        onProgress(
          ModelDownloadEvent(
            transferredBytes: received,
            connecting: false,
            sourceLabel: source.label,
          ),
        );
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != expectedBytes) {
        throw const FormatException('模型下载不完整，将在下次继续');
      }
    } catch (_) {
      if (canceled || shouldCancel?.call() == true) {
        throw const ModelDownloadCanceled();
      }
      rethrow;
    } finally {
      cancellationTimer?.cancel();
      await output?.close();
      client.close(force: true);
    }
  }
}
