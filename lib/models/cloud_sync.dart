enum CloudSyncProvider { webDav, s3 }

extension CloudSyncProviderLabel on CloudSyncProvider {
  String get label => switch (this) {
    CloudSyncProvider.webDav => 'WebDAV',
    CloudSyncProvider.s3 => 'S3',
  };
}

class WebDavSyncConfig {
  final String serverUrl;
  final String username;
  final String password;
  final String remoteFolder;

  const WebDavSyncConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteFolder = 'FKNotes',
  });

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
    'remoteFolder': remoteFolder,
  };

  factory WebDavSyncConfig.fromJson(Object? value) {
    final json = value is Map ? value : const {};
    return WebDavSyncConfig(
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remoteFolder: json['remoteFolder'] as String? ?? 'FKNotes',
    );
  }
}

class S3SyncConfig {
  final String endpoint;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String prefix;
  final bool pathStyle;

  const S3SyncConfig({
    this.endpoint = '',
    this.region = 'us-east-1',
    this.bucket = '',
    this.accessKeyId = '',
    this.secretAccessKey = '',
    this.prefix = 'FKNotes',
    this.pathStyle = true,
  });

  Map<String, Object?> toJson() => {
    'endpoint': endpoint,
    'region': region,
    'bucket': bucket,
    'accessKeyId': accessKeyId,
    'secretAccessKey': secretAccessKey,
    'prefix': prefix,
    'pathStyle': pathStyle,
  };

  factory S3SyncConfig.fromJson(Object? value) {
    final json = value is Map ? value : const {};
    return S3SyncConfig(
      endpoint: json['endpoint'] as String? ?? '',
      region: json['region'] as String? ?? 'us-east-1',
      bucket: json['bucket'] as String? ?? '',
      accessKeyId: json['accessKeyId'] as String? ?? '',
      secretAccessKey: json['secretAccessKey'] as String? ?? '',
      prefix: json['prefix'] as String? ?? 'FKNotes',
      pathStyle: json['pathStyle'] as bool? ?? true,
    );
  }
}

class CloudSyncSettings {
  final CloudSyncProvider provider;
  final WebDavSyncConfig webDav;
  final S3SyncConfig s3;
  final String deviceId;
  final String? lastSyncedContentDigest;
  final String? lastRemoteRevision;
  final DateTime? lastSyncedAt;

  const CloudSyncSettings({
    this.provider = CloudSyncProvider.webDav,
    this.webDav = const WebDavSyncConfig(),
    this.s3 = const S3SyncConfig(),
    this.deviceId = '',
    this.lastSyncedContentDigest,
    this.lastRemoteRevision,
    this.lastSyncedAt,
  });

  bool get configured => configurationProblem == null;

  String? get configurationProblem {
    switch (provider) {
      case CloudSyncProvider.webDav:
        final uri = Uri.tryParse(webDav.serverUrl.trim());
        if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
          return '请输入完整的 WebDAV 地址';
        }
        if (uri.scheme != 'https') return 'WebDAV 地址必须使用 HTTPS';
        if (uri.userInfo.isNotEmpty) return '请不要在 WebDAV 地址中填写账号密码';
        if (uri.hasQuery || uri.hasFragment) return 'WebDAV 地址不能包含查询参数或片段';
        if (webDav.username.trim().isEmpty) return '请输入 WebDAV 用户名';
        if (webDav.username.contains(':')) return 'WebDAV 用户名不能包含冒号';
        if (webDav.password.isEmpty) return '请输入 WebDAV 密码';
        if (_unsafeRemotePath(webDav.remoteFolder)) return '远程目录名称不安全';
        return null;
      case CloudSyncProvider.s3:
        final uri = Uri.tryParse(s3.endpoint.trim());
        if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
          return '请输入完整的 S3 Endpoint';
        }
        if (uri.scheme != 'https') return 'S3 Endpoint 必须使用 HTTPS';
        if (uri.userInfo.isNotEmpty) return '请不要在 S3 Endpoint 中填写账号密码';
        if (uri.hasQuery || uri.hasFragment) return 'S3 Endpoint 不能包含查询参数或片段';
        if (s3.region.trim().isEmpty) return '请输入 S3 Region';
        if (s3.bucket.trim().isEmpty) return '请输入 Bucket';
        if (s3.accessKeyId.trim().isEmpty) return '请输入 Access Key ID';
        if (s3.secretAccessKey.isEmpty) return '请输入 Secret Access Key';
        if (_unsafeRemotePath(s3.prefix)) return '对象前缀不安全';
        return null;
    }
  }

  CloudSyncSettings copyWith({
    CloudSyncProvider? provider,
    WebDavSyncConfig? webDav,
    S3SyncConfig? s3,
    String? deviceId,
    String? lastSyncedContentDigest,
    String? lastRemoteRevision,
    DateTime? lastSyncedAt,
    bool clearSyncState = false,
  }) => CloudSyncSettings(
    provider: provider ?? this.provider,
    webDav: webDav ?? this.webDav,
    s3: s3 ?? this.s3,
    deviceId: deviceId ?? this.deviceId,
    lastSyncedContentDigest: clearSyncState
        ? null
        : lastSyncedContentDigest ?? this.lastSyncedContentDigest,
    lastRemoteRevision: clearSyncState
        ? null
        : lastRemoteRevision ?? this.lastRemoteRevision,
    lastSyncedAt: clearSyncState ? null : lastSyncedAt ?? this.lastSyncedAt,
  );

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'provider': provider.name,
    'webDav': webDav.toJson(),
    's3': s3.toJson(),
    'deviceId': deviceId,
    'lastSyncedContentDigest': lastSyncedContentDigest,
    'lastRemoteRevision': lastRemoteRevision,
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
  };

  factory CloudSyncSettings.fromJson(Object? value) {
    final json = value is Map ? value : const {};
    final providerName = json['provider'] as String?;
    final provider = CloudSyncProvider.values.firstWhere(
      (candidate) => candidate.name == providerName,
      orElse: () => CloudSyncProvider.webDav,
    );
    return CloudSyncSettings(
      provider: provider,
      webDav: WebDavSyncConfig.fromJson(json['webDav']),
      s3: S3SyncConfig.fromJson(json['s3']),
      deviceId: json['deviceId'] as String? ?? '',
      lastSyncedContentDigest: json['lastSyncedContentDigest'] as String?,
      lastRemoteRevision: json['lastRemoteRevision'] as String?,
      lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
    );
  }

  static bool _unsafeRemotePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final segments = trimmed.replaceAll('\\', '/').split('/');
    return segments.any(
      (segment) => segment == '..' || segment == '.' || segment.isEmpty,
    );
  }
}

class CloudSnapshotMetadata {
  final String revision;
  final String archiveKey;
  final String deviceId;
  final DateTime createdAt;
  final String contentDigest;
  final String archiveSha256;
  final int sizeBytes;

  const CloudSnapshotMetadata({
    required this.revision,
    required this.archiveKey,
    required this.deviceId,
    required this.createdAt,
    required this.contentDigest,
    required this.archiveSha256,
    required this.sizeBytes,
  });

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'revision': revision,
    'archiveKey': archiveKey,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'contentDigest': contentDigest,
    'archiveSha256': archiveSha256,
    'sizeBytes': sizeBytes,
  };

  factory CloudSnapshotMetadata.fromJson(Object? value) {
    if (value is! Map || value['formatVersion'] != 1) {
      throw const FormatException('云端同步清单格式不受支持');
    }
    final revision = value['revision'];
    final archiveKey = value['archiveKey'];
    final deviceId = value['deviceId'];
    final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
    final contentDigest = value['contentDigest'];
    final archiveSha256 = value['archiveSha256'];
    final sizeBytes = value['sizeBytes'];
    if (revision is! String ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(revision) ||
        archiveKey is! String ||
        !RegExp(
          r'^snapshots/[A-Za-z0-9._-]+\.fknotes\.zip$',
        ).hasMatch(archiveKey) ||
        archiveKey != 'snapshots/$revision.fknotes.zip' ||
        deviceId is! String ||
        createdAt == null ||
        contentDigest is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(contentDigest) ||
        archiveSha256 is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(archiveSha256) ||
        sizeBytes is! int ||
        sizeBytes <= 0) {
      throw const FormatException('云端同步清单不完整');
    }
    return CloudSnapshotMetadata(
      revision: revision,
      archiveKey: archiveKey,
      deviceId: deviceId,
      createdAt: createdAt.toUtc(),
      contentDigest: contentDigest,
      archiveSha256: archiveSha256,
      sizeBytes: sizeBytes,
    );
  }
}

enum CloudSyncResultType { uploaded, downloaded, unchanged, conflict }

class CloudSyncResult {
  final CloudSyncResultType type;
  final CloudSnapshotMetadata? remote;

  const CloudSyncResult(this.type, {this.remote});
}

enum CloudSyncConflictResolution { keepLocal, useRemote }
