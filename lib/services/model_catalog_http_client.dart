import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../debug/app_diagnostics.dart';
import 'model_download_source_policy.dart';
import 'model_download_transport.dart';

enum ModelCatalogFailureKind {
  timeout,
  offline,
  unauthorized,
  serviceUnavailable,
  invalidResponse,
}

class ModelCatalogRequestException implements Exception {
  final ModelCatalogFailureKind kind;
  final String debugDetails;

  const ModelCatalogRequestException(this.kind, {this.debugDetails = ''});

  @override
  String toString() => 'Model catalog request failed (${kind.name})';
}

typedef ModelCatalogSourceFetch =
    Future<Uint8List> Function(ModelDownloadSource source);

/// Fetches small Hugging Face catalog/metadata resources with the same source
/// preference as model downloads. A mirror redirecting back to Hugging Face is
/// rejected so it cannot be reported as a healthy independent endpoint.
class ModelCatalogHttpClient {
  ModelCatalogHttpClient({
    ModelDownloadSourcePolicy? sourcePolicy,
    this._sourceFetch,
  }) : _sourcePolicy = sourcePolicy ?? ModelDownloadSourcePolicy.instance;

  static final instance = ModelCatalogHttpClient();

  final ModelDownloadSourcePolicy _sourcePolicy;
  final ModelCatalogSourceFetch? _sourceFetch;

  Future<Uint8List> get(Uri officialUri) async {
    if (officialUri.host != 'huggingface.co') {
      throw const ModelCatalogRequestException(
        ModelCatalogFailureKind.invalidResponse,
        debugDetails: 'Only huggingface.co catalog resources are supported',
      );
    }
    final sources = _sourcePolicy.order([
      ModelDownloadSource(
        uri: officialUri,
        label: 'Hugging Face',
        kind: ModelDownloadSourceKind.official,
      ),
      ModelDownloadSource(
        uri: officialUri.replace(host: 'hf-mirror.com'),
        label: '第三方国内镜像',
        kind: ModelDownloadSourceKind.mainlandMirror,
      ),
    ]);
    final failures = <ModelCatalogRequestException>[];
    for (final source in sources) {
      final stopwatch = Stopwatch()..start();
      if (kDebugMode) {
        AppDiagnostics.debug(
          AppLogCategory.network,
          'model_catalog_source_attempted',
          data: {'source': source.label, 'host': source.uri.host},
        );
      }
      try {
        final bytes = await (_sourceFetch?.call(source) ?? _read(source));
        _sourcePolicy.reportSuccessfulSource(source);
        if (kDebugMode) {
          AppDiagnostics.info(
            AppLogCategory.network,
            'model_catalog_source_succeeded',
            data: {
              'source': source.label,
              'host': source.uri.host,
              'durationMs': stopwatch.elapsedMilliseconds,
              'responseBytes': bytes.length,
            },
          );
        }
        return bytes;
      } on ModelCatalogRequestException catch (error) {
        failures.add(error);
        if (kDebugMode) {
          AppDiagnostics.warning(
            AppLogCategory.network,
            'model_catalog_source_failed',
            data: {
              'source': source.label,
              'host': source.uri.host,
              'durationMs': stopwatch.elapsedMilliseconds,
              'failureKind': error.kind.name,
              'debugDetails': error.debugDetails,
            },
            error: error,
          );
        }
      }
    }
    final kind =
        failures.any(
          (failure) => failure.kind == ModelCatalogFailureKind.timeout,
        )
        ? ModelCatalogFailureKind.timeout
        : failures.any(
            (failure) => failure.kind == ModelCatalogFailureKind.unauthorized,
          )
        ? ModelCatalogFailureKind.unauthorized
        : failures.any(
            (failure) =>
                failure.kind == ModelCatalogFailureKind.serviceUnavailable,
          )
        ? ModelCatalogFailureKind.serviceUnavailable
        : ModelCatalogFailureKind.offline;
    throw ModelCatalogRequestException(
      kind,
      debugDetails: failures.map((failure) => failure.debugDetails).join(' | '),
    );
  }

  Future<Uint8List> _read(ModelDownloadSource source) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      var uri = source.uri;
      for (var redirects = 0; redirects <= 2; redirects++) {
        try {
          final request = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 5));
          request
            ..followRedirects = false
            ..headers.set(HttpHeaders.userAgentHeader, 'fknotes/model-catalog');
          final response = await request.close().timeout(
            const Duration(seconds: 6),
          );
          if (_isRedirect(response.statusCode)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location == null) {
              throw const ModelCatalogRequestException(
                ModelCatalogFailureKind.invalidResponse,
                debugDetails: 'Redirect without Location header',
              );
            }
            final redirected = uri.resolve(location);
            if (source.kind == ModelDownloadSourceKind.mainlandMirror &&
                redirected.host != uri.host) {
              throw ModelCatalogRequestException(
                ModelCatalogFailureKind.serviceUnavailable,
                debugDetails:
                    'Mirror redirected to ${redirected.host} instead of '
                    'serving the resource',
              );
            }
            uri = redirected;
            continue;
          }
          if (response.statusCode == HttpStatus.unauthorized ||
              response.statusCode == HttpStatus.forbidden) {
            throw ModelCatalogRequestException(
              ModelCatalogFailureKind.unauthorized,
              debugDetails: 'HTTP ${response.statusCode} from ${uri.host}',
            );
          }
          if (response.statusCode != HttpStatus.ok) {
            throw ModelCatalogRequestException(
              ModelCatalogFailureKind.serviceUnavailable,
              debugDetails: 'HTTP ${response.statusCode} from ${uri.host}',
            );
          }
          final builder = BytesBuilder(copy: false);
          var size = 0;
          await for (final chunk in response.timeout(
            const Duration(seconds: 8),
          )) {
            size += chunk.length;
            if (size > 8 * 1024 * 1024) {
              throw const ModelCatalogRequestException(
                ModelCatalogFailureKind.invalidResponse,
                debugDetails: 'Catalog response exceeded 8 MB',
              );
            }
            builder.add(chunk);
          }
          return builder.takeBytes();
        } on TimeoutException catch (error) {
          throw ModelCatalogRequestException(
            ModelCatalogFailureKind.timeout,
            debugDetails: '${uri.host}: $error',
          );
        } on SocketException catch (error) {
          final timedOut = error.message.toLowerCase().contains('timed out');
          throw ModelCatalogRequestException(
            timedOut
                ? ModelCatalogFailureKind.timeout
                : ModelCatalogFailureKind.offline,
            debugDetails: '${uri.host}: $error',
          );
        } on HandshakeException catch (error) {
          throw ModelCatalogRequestException(
            ModelCatalogFailureKind.offline,
            debugDetails: '${uri.host}: $error',
          );
        }
      }
      throw const ModelCatalogRequestException(
        ModelCatalogFailureKind.serviceUnavailable,
        debugDetails: 'Too many redirects',
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
