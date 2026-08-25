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

  AndroidBridgeUpdateService({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _client = client ?? http.Client(),
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
    } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
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
    final cleanPath = downloadPath.startsWith('/') ? downloadPath : '/$downloadPath';
    return Uri.parse('$baseUrl$cleanPath');
  }

  /// Fetch release manifest from Bridge.
  Future<BridgeReleaseManifest> fetchManifest(String bridgeUrl) async {
    final uri = buildManifestUri(bridgeUrl);
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 10));

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
    final appCode = currentVersionCode ?? await _getCurrentVersionCode();
    return manifest.versionCode > appCode;
  }

  Future<int> _getCurrentVersionCode() async {
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
  }) async {
    final downloadUri = buildDownloadUri(bridgeUrl, manifest.downloadPath);
    final request = http.Request('GET', downloadUri);
    final streamedResponse = await _client.send(request);

    if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
      throw HttpException(
        'Download failed with status ${streamedResponse.statusCode}',
        uri: downloadUri,
      );
    }

    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/anycoding-update-${manifest.versionCode}.apk');
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final sink = apkFile.openWrite();
    int received = 0;
    final total = streamedResponse.contentLength ?? manifest.size;

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }

    await sink.flush();
    await sink.close();

    // Verify SHA-256
    final downloadedBytes = await apkFile.readAsBytes();
    final digest = sha256.convert(downloadedBytes).toString();

    if (digest.toLowerCase() != manifest.sha256.toLowerCase()) {
      await apkFile.delete();
      throw Exception(
        'APK SHA-256 verification failed! Expected ${manifest.sha256}, got $digest',
      );
    }

    return apkFile.path;
  }

  /// Launch Android system package installer for downloaded APK.
  Future<bool> launchInstaller(String apkFilePath) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Package installer is only supported on Android');
    }

    final result = await _installerChannel.invokeMethod<bool>(
      'installApk',
      {'filePath': apkFilePath},
    );
    return result ?? false;
  }
}
