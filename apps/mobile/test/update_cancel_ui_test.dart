import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ccpocket/services/android_bridge_update_service.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/features/anycoding/widgets/anycoding_update_sheet.dart';

class ControlledDownload extends AndroidBridgeUpdateService {
  ControlledDownload()
    : super(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'versionCode': 231,
              'versionName': '1.115.16',
              'size': 4,
              'sha256': 'test',
            }),
            200,
          ),
        ),
        packageInfoLoader: () async => PackageInfo(
          appName: 'AnyCoding',
          packageName: 'com.k9i.ccpocket',
          version: '1.115.15',
          buildNumber: '230',
        ),
      );
  UpdateDownloadCancellation? token;
  @override
  Future<String> downloadAndVerifyApk({
    required String bridgeUrl,
    required BridgeReleaseManifest manifest,
    void Function(int, int)? onProgress,
    Future<String> Function()? retryBridgeUrl,
    UpdateDownloadCancellation? cancellation,
    void Function(int)? onRetry,
    void Function()? onVerifying,
  }) async {
    token = cancellation;
    onRetry?.call(2);
    await cancellation!.signal;
    throw const UpdateDownloadCancelled();
  }
}

void main() {
  for (final dismiss in [false, true]) {
    testWidgets(
      '${dismiss ? "closing sheet" : "cancel button"} cancels download',
      (tester) async {
        final service = ControlledDownload();
        final bridge = BridgeService();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnyCodingUpdateSheet(
                bridge: bridge,
                updateService: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('下载并安装更新'));
        await tester.tap(find.text('下载并安装更新'));
        await tester.pump();
        expect(find.text('连接中断，正在重试（2/3）'), findsOneWidget);
        if (dismiss) {
          await tester.pumpWidget(const SizedBox());
        } else {
          final button = find.byKey(
            const ValueKey('cancel_update_download_button'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.text('下载并安装更新'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }
        expect(service.token!.isCancelled, true);
        expect(tester.takeException(), isNull);
        bridge.dispose();
      },
    );
  }
}
