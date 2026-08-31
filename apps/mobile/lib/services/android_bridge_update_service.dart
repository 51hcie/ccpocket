import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Manifest served by Bridge release endpoint.
class BridgeReleaseManifest {
  final int versionCode;
  final String versionName;
  final String sha256;
  final int size;
  final String buildTime;
  final String downloadPath;
  final String changelog;
  final String? certificateSha256;

  const BridgeReleaseManifest({
    required this.versionCode,
    required this.versionName,
    required this.sha256,
    required this.size,
    required this.buildTime,
    required this.downloadPath,
    this.changelog = '',
    this.certificateSha256,
  });

  factory BridgeReleaseManifest.fromJson(Map<String, dynamic> json) {
    return BridgeReleaseManifest(
      versionCode: json['versionCode'] as int? ?? 0,
      versionName: json['versionName'] as String? ?? '0.0.0',
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      buildTime: json['buildTime'] as String? ?? '',
      downloadPath: json['downloadPath'] as String? ?? '/api/update/download',
      changelog: json['changelog'] as String? ?? '',
      certificateSha256: json['certificateSha256'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'versionCode': versionCode,
    'versionName': versionName,
    'sha256': sha256,
    'size': size,
    'buildTime': buildTime,
    'downloadPath': downloadPath,
    'changelog': changelog,
    if (certificateSha256 != null) 'certificateSha256': certificateSha256,
  };
}

enum UpdateCheckStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  verifying,
  readyToInstall,
  error,
}

class AndroidBridgeUpdateService {
  static const MethodChannel _installerChannel = MethodChannel(
    'ccpocket/android_installer',
  );

  final http.Client _client;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<Directory> Function() _temporaryDirectory;
  final Duration downloadTimeout;

  AndroidBridgeUpdateService({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<Directory> Function()? temporaryDirectory,
    this.downloadTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  /// Derive HTTP base URL from Bridge WebSocket URL.
  /// Handles IPv4, localhost, domain, and literal IPv6 bracketed hosts.
  static String deriveHttpBaseUrl(String? wsUrl) {
    if (wsUrl == null || wsUrl.trim().isEmpty) {
      return 'http://127.0.0.1:8766';
    }

    final trimmed = wsUrl.trim();
    String scheme = 'http';
    String authority = trimmed;

    if (trimmed.startsWith('wss://')) {
      scheme = 'https';
      authority = trimmed.substring(6);
    } else if (trimmed.startsWith('ws://')) {
      scheme = 'http';
      authority = trimmed.substring(5);
    } else if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      return trimmed.replaceAll(RegExp(r'/+$'), '');
    }

    // Strip trailing path/query if any
    final slashIndex = authority.indexOf('/');
    if (slashIndex != -1) {
      authority = authority.substring(0, slashIndex);
    }
    final questionIndex = authority.indexOf('?');
    if (questionIndex != -1) {
      authority = authority.substring(0, questionIndex);
    }

    return '$scheme://$authority';
  }

  /// Construct manifest URL given Bridge base or WebSocket URL.
  static Uri buildManifestUri(String bridgeUrl) {
    final baseUrl = deriveHttpBaseUrl(bridgeUrl);
    return Uri.parse('$baseUrl/api/update/manifest');
  }

  /// Construct download URL given Bridge base or WebSocket URL and download path.
  static Uri buildDownloadUri(String bridgeUrl, String downloadPath) {
    final baseUrl = deriveHttpBaseUrl(bridgeUrl);
    final cleanPath = downloadPath.startsWith('/')
        ? downloadPath
        : '/$downloadPath';
    return Uri.parse('$baseUrl$cleanPath');
  }

  /// Fetch release manifest from Bridge.
  Future<BridgeReleaseManifest> fetchManifest(String bridgeUrl) async {
    final uri = buildManifestUri(bridgeUrl);
    final response = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw HttpException(
        'Bridge returned status ${response.statusCode}',
        uri: uri,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return BridgeReleaseManifest.fromJson(json);
  }

  /// Compare manifest versionCode against current app versionCode.
  Future<bool> isUpdateAvailable(
    BridgeReleaseManifest manifest, {
    int? currentVersionCode,
  }) async {
    final appCode = currentVersionCode ?? await getCurrentVersionCode();
    return manifest.versionCode > appCode;
  }

  Future<int> getCurrentVersionCode() async {
    try {
      final info = await _packageInfoLoader();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String> getCurrentVersionName() async {
    try {
      final info = await _packageInfoLoader();
      return info.version;
    } catch (_) {
      return '1.115.2';
    }
  }

  /// Download APK with progress callback, verify SHA-256, and return local file path.
  Future<String> downloadAndVerifyApk({
    required String bridgeUrl,
    required BridgeReleaseManifest manifest,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    Future<String> Function()? retryBridgeUrl,
  }) async {
    var url = bridgeUrl;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _downloadAttempt(url, manifest, onProgress);
      } catch (error) {
        final transient =
            error is TimeoutException ||
            error is SocketException ||
            error is http.ClientException;
        if (!transient || attempt == 2) rethrow;
        if (retryBridgeUrl != null) url = await retryBridgeUrl();
      }
    }
    throw StateError('Download attempts exhausted');
  }

  Future<String> _downloadAttempt(
    String bridgeUrl,
    BridgeReleaseManifest manifest,
    void Function(int, int)? onProgress,
  ) async {
    final downloadUri = buildDownloadUri(bridgeUrl, manifest.downloadPath);
    final abort = Completer<void>();
    Directory? directory;
    RandomAccessFile? output;
    var verified = false;
    try {
      final request = http.AbortableRequest(
        'GET',
        downloadUri,
        abortTrigger: abort.future,
      );
      final streamedResponse = await _client
          .send(request)
          .timeout(downloadTimeout);
      // No Range request is sent: a partial response is not a complete APK.
      if (streamedResponse.statusCode != 200) {
        throw HttpException(
          'Download failed with status ${streamedResponse.statusCode}',
          uri: downloadUri,
        );
      }

      final temp = await _temporaryDirectory();
      directory = await temp.createTemp('anycoding-update-');
      final apkFile = File(
        '${directory.path}/anycoding-${manifest.versionCode}.apk',
      );
      output = await apkFile.open(mode: FileMode.write);
      int received = 0;
      onProgress?.call(0, manifest.size);
      await for (final chunk in streamedResponse.stream.timeout(
        downloadTimeout,
      )) {
        await output.writeFrom(chunk);
        received += chunk.length;
        if (received > manifest.size) {
          throw const FormatException('APK size mismatch');
        }
        onProgress?.call(received, manifest.size);
      }
      await output.close();
      output = null;
      if (received != manifest.size) {
        throw const FormatException('APK size mismatch');
      }

      // Verify SHA-256
      final digest = (await sha256.bind(apkFile.openRead()).first).toString();

      if (digest.toLowerCase() != manifest.sha256.toLowerCase()) {
        throw Exception(
          'APK SHA-256 verification failed! Expected ${manifest.sha256}, got $digest',
        );
      }

      // Reuse the verified package for this version rather than accumulating
      // a new 200 MB copy every time the update sheet is opened.
      final installedFile = await apkFile.rename(
        '${temp.path}/anycoding-update-${manifest.versionCode}.apk',
      );
      await directory.delete();
      verified = true;
      return installedFile.path;
    } finally {
      abort.complete();
      await output?.close();
      if (!verified && directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  /// Launch Android system package installer for downloaded APK.
  Future<bool> launchInstaller(String apkFilePath) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Package installer is only supported on Android');
    }

    final result = await _installerChannel.invokeMethod<bool>('installApk', {
      'filePath': apkFilePath,
    });
    return result ?? false;
  }
}
