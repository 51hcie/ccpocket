import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:ccpocket/services/android_bridge_update_service.dart';
import 'package:ccpocket/features/anycoding/widgets/anycoding_update_sheet.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/theme/app_theme.dart';

void main() {
  group('AndroidBridgeUpdateService URL Derivation Tests', () {
    test('derives http url from ws localhost url', () {
      final url = AndroidBridgeUpdateService.deriveHttpBaseUrl('ws://127.0.0.1:8766');
      expect(url, 'http://127.0.0.1:8766');
    });

    test('derives http url from wss domain url', () {
      final url = AndroidBridgeUpdateService.deriveHttpBaseUrl('wss://mac.local:8765');
      expect(url, 'https://mac.local:8765');
    });

    test('derives http url from literal bracketed IPv6 websocket URL', () {
      final url = AndroidBridgeUpdateService.deriveHttpBaseUrl(
        'ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
      expect(url, 'http://[2408:824e:158d:5a80:875:122:45bf:5441]:8766');
    });

    test('derives manifest URI properly for IPv6 host', () {
      final uri = AndroidBridgeUpdateService.buildManifestUri(
        'ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
      );
      expect(
        uri.toString(),
        'http://[2408:824e:158d:5a80:875:122:45bf:5441]:8766/api/update/manifest',
      );
    });

    test('derives download URI properly for IPv6 host', () {
      final uri = AndroidBridgeUpdateService.buildDownloadUri(
        'ws://[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
        '/api/update/download',
      );
      expect(
        uri.toString(),
        'http://[2408:824e:158d:5a80:875:122:45bf:5441]:8766/api/update/download',
      );
    });
  });

  group('Manifest Parsing and Version Comparison', () {
    test('parses manifest JSON accurately', () {
      final json = {
        'versionCode': 218,
        'versionName': '1.115.3',
        'sha256': '59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2',
        'size': 1048576,
        'buildTime': '2026-08-25T12:00:00Z',
        'downloadPath': '/api/update/download',
        'changelog': 'Batch 2 Usability Release',
      };

      final manifest = BridgeReleaseManifest.fromJson(json);
      expect(manifest.versionCode, 218);
      expect(manifest.versionName, '1.115.3');
      expect(manifest.size, 1048576);
      expect(manifest.changelog, 'Batch 2 Usability Release');
    });

    test('detects update available when manifest versionCode is greater', () async {
      final service = AndroidBridgeUpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'AnyCoding',
          packageName: 'com.k9i.ccpocket',
          version: '1.115.2',
          buildNumber: '217',
        ),
      );

      const newerManifest = BridgeReleaseManifest(
        versionCode: 218,
        versionName: '1.115.3',
        sha256: 'abc',
        size: 100,
        buildTime: '2026-08-25',
        downloadPath: '/api/update/download',
      );

      final hasUpdate = await service.isUpdateAvailable(newerManifest);
      expect(hasUpdate, true);
    });

    test('detects up to date when manifest versionCode is equal or lower', () async {
      final service = AndroidBridgeUpdateService(
        packageInfoLoader: () async => PackageInfo(
          appName: 'AnyCoding',
          packageName: 'com.k9i.ccpocket',
          version: '1.115.2',
          buildNumber: '217',
        ),
      );

      const sameManifest = BridgeReleaseManifest(
        versionCode: 217,
        versionName: '1.115.2',
        sha256: 'abc',
        size: 100,
        buildTime: '2026-08-25',
        downloadPath: '/api/update/download',
      );

      final hasUpdate = await service.isUpdateAvailable(sameManifest);
      expect(hasUpdate, false);
    });
  });

  group('AnyCodingUpdateSheet Widget Tests', () {
    testWidgets('renders update sheet with update available state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'versionCode': 218,
              'versionName': '1.115.3',
              'sha256': '59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2',
              'size': 5242880,
              'buildTime': '2026-08-25T12:00:00Z',
              'downloadPath': '/api/update/download',
              'changelog': 'Typography & Monitor Console',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mockService = AndroidBridgeUpdateService(
        client: mockClient,
        packageInfoLoader: () async => PackageInfo(
          appName: 'AnyCoding',
          packageName: 'com.k9i.ccpocket',
          version: '1.115.2',
          buildNumber: '217',
        ),
      );

      final bridge = BridgeService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AnyCodingUpdateSheet(
              bridge: bridge,
              updateService: mockService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('检查 AnyCoding 更新'), findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('v1.115.3 (Build 218)'), findsOneWidget);
      expect(find.text('Typography & Monitor Console'), findsOneWidget);
      expect(find.text('下载并安装更新'), findsOneWidget);
    });

    testWidgets('renders up to date state correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'versionCode': 217,
              'versionName': '1.115.2',
              'sha256': '59186b6981215494ee6e21e8a988dc7a434eb7ffa40bfc226e9dbdbc585cb2d2',
              'size': 5242880,
              'buildTime': '2026-08-25T12:00:00Z',
              'downloadPath': '/api/update/download',
              'changelog': '',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mockService = AndroidBridgeUpdateService(
        client: mockClient,
        packageInfoLoader: () async => PackageInfo(
          appName: 'AnyCoding',
          packageName: 'com.k9i.ccpocket',
          version: '1.115.2',
          buildNumber: '217',
        ),
      );

      final bridge = BridgeService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AnyCodingUpdateSheet(
              bridge: bridge,
              updateService: mockService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.text('重新下载当前版本 APK'), findsOneWidget);
    });
  });
}
