import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ccpocket/services/bridge_monitoring_service.dart';
import 'package:ccpocket/features/anycoding/views/anycoding_monitoring_view.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/theme/app_theme.dart';

void main() {
  group('BridgeMonitoringService Data Parsing Tests', () {
    test('parses full monitoring payload JSON correctly', () {
      final json = {
        'timestamp': '2026-08-25T12:00:00Z',
        'system': {
          'available': true,
          'hostname': 'Lws-MacBook-Pro.local',
          'os': 'macOS 15.0 (arm64)',
          'systemUptime': 172800,
          'cpu': {
            'model': 'Apple M3 Max',
            'cores': 14,
            'speedMHz': 4050,
            'loadPercent': 24.5,
          },
          'memory': {
            'totalBytes': 38654705664,
            'freeBytes': 12884901888,
            'usedBytes': 25769803776,
            'usedPercent': 66.7,
          },
          'disk': {
            'available': true,
            'totalBytes': 1000000000000,
            'freeBytes': 500000000000,
            'usedBytes': 500000000000,
            'usedPercent': 50.0,
            'mountPoint': '/',
          },
          'loadAverage': [1.8, 1.4, 1.2],
          'source': 'macOS Kernel / OS Runtime',
        },
        'bridge': {
          'available': true,
          'uptime': 3600,
          'port': 8766,
          'connectedClients': 2,
          'taskCounts': {
            'running': 1,
            'queued': 0,
            'completed': 12,
            'failed': 0,
          },
          'source': 'AnyCoding Bridge Runtime',
        },
        'codex': {
          'available': true,
          'account': 'user_***',
          'plan': 'ChatGPT Pro (Authoritative)',
          'fiveHourWindow': {
            'usedPercent': 18.5,
            'resetsAt': '2026-08-25T17:00:00Z',
          },
          'sevenDayWindow': {
            'usedPercent': 42.0,
            'resetsAt': '2026-08-30T00:00:00Z',
          },
          'tokenUsage': {
            'inputTokens': 15000,
            'outputTokens': 3000,
            'totalTokens': 18000,
          },
          'source': 'Codex App Server / Local Sessions',
        },
        'antigravity': {
          'available': true,
          'model': 'gemini-3.7-flash-high',
          'status': 'Ready',
          'quota': '当前版本暂不可获取',
          'note': 'Antigravity CLI 本地接口当前不提供实时配额查询，按实际执行计费',
          'source': 'Antigravity CLI (Local)',
        },
      };

      final data = MonitoringDataModel.fromJson(json);
      expect(data.system.hostname, 'Lws-MacBook-Pro.local');
      expect(data.system.cpu.cores, 14);
      expect(data.system.memory.usedPercent, 66.7);
      expect(data.system.disk.available, true);
      expect(data.bridge.port, 8766);
      expect(data.bridge.taskCounts.completed, 12);
      expect(data.codex.account, 'user_***');
      expect(data.codex.fiveHourWindow?.usedPercent, 18.5);
      expect(data.antigravity.quota, '当前版本暂不可获取');
      expect(data.antigravity.source, 'Antigravity CLI (Local)');
    });
  });

  group('AnyCodingMonitoringSheet Widget & Text Scale Tests', () {
    Widget buildTestWidget({
      required BridgeMonitoringService service,
      double textScaleFactor = 1.0,
      Size size = const Size(375, 812),
    }) {
      final bridge = BridgeService();
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: Scaffold(
            body: AnyCodingMonitoringSheet(
              bridge: bridge,
              monitoringService: service,
            ),
          ),
        ),
      );
    }

    testWidgets('renders real monitoring cards cleanly on phone viewport at text scale 1.0', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.875;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/monitor')) {
          return http.Response(
            jsonEncode({
              'timestamp': '2026-08-25T12:00:00Z',
              'system': {
                'available': true,
                'hostname': 'Lws-MacBook-Pro.local',
                'os': 'macOS 15.0 (arm64)',
                'systemUptime': 86400,
                'cpu': {
                  'model': 'Apple M3 Max',
                  'cores': 14,
                  'speedMHz': 4050,
                  'loadPercent': 15.0,
                },
                'memory': {
                  'totalBytes': 38654705664,
                  'freeBytes': 19327352832,
                  'usedBytes': 19327352832,
                  'usedPercent': 50.0,
                },
                'disk': {
                  'available': true,
                  'totalBytes': 1000000000000,
                  'freeBytes': 600000000000,
                  'usedBytes': 400000000000,
                  'usedPercent': 40.0,
                  'mountPoint': '/',
                },
                'loadAverage': [1.2, 1.1, 0.9],
                'source': 'macOS Kernel / OS Runtime',
              },
              'bridge': {
                'available': true,
                'uptime': 3600,
                'port': 8766,
                'connectedClients': 1,
                'taskCounts': {
                  'running': 0,
                  'queued': 0,
                  'completed': 5,
                  'failed': 0,
                },
                'source': 'AnyCoding Bridge Runtime',
              },
              'codex': {
                'available': true,
                'account': 'user_***',
                'plan': 'plus',
                'fiveHourWindow': {
                  'usedPercent': 12.0,
                  'resetsAt': '2026-08-25T17:00:00Z',
                },
                'sevenDayWindow': {
                  'usedPercent': 54.0,
                  'resetsAt': '2026-08-30T00:00:00Z',
                },
                'source': 'Codex App Server / Local Sessions',
              },
              'antigravity': {
                'available': true,
                'model': 'gemini-3.7-flash-high',
                'status': 'Ready',
                'quota': '当前版本暂不可获取',
                'note': 'Antigravity CLI 本地接口当前不提供实时配额查询，按实际执行计费',
                'source': 'Antigravity CLI (Local)',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = BridgeMonitoringService(client: mockClient);

      await tester.pumpWidget(buildTestWidget(service: service, textScaleFactor: 1.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Mac 监控控制台'), findsOneWidget);
      expect(find.text('Lws-MacBook-Pro.local'), findsOneWidget);
      expect(find.text('Mac 主机系统'), findsOneWidget);
      expect(find.text('Bridge 运行时与任务队列'), findsOneWidget);
      expect(find.text('Codex 引擎配额'), findsOneWidget);
      expect(find.text('Antigravity 引擎'), findsOneWidget);
      expect(find.text('当前版本暂不可获取'), findsOneWidget);
    });

    testWidgets('renders all real monitoring cards on compact phone viewport at text scale 1.3 without overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.875;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'timestamp': '2026-08-25T12:00:00Z',
            'system': {
              'available': true,
              'hostname': 'lwdeMacBook-Pro.local',
              'os': 'macOS 13.7.8 (x64)',
              'systemUptime': 1390800,
              'cpu': {'model': 'Intel Core i9', 'cores': 8, 'speedMHz': 2300, 'loadPercent': 57.8},
              'memory': {'totalBytes': 34359738368, 'freeBytes': 1475739648, 'usedBytes': 32884000000, 'usedPercent': 95.7},
              'disk': {'available': true, 'totalBytes': 250685575168, 'freeBytes': 152290615296, 'usedBytes': 98394959872, 'usedPercent': 39.2, 'mountPoint': '/'},
              'loadAverage': [4.62, 4.41, 4.31],
              'source': 'macOS Kernel / OS Runtime',
            },
            'bridge': {
              'available': true,
              'uptime': 412,
              'port': 8766,
              'connectedClients': 1,
              'taskCounts': {'running': 0, 'queued': 0, 'completed': 6, 'failed': 0},
              'source': 'AnyCoding Bridge Runtime',
            },
            'codex': {
              'available': true,
              'account': 'user_***',
              'plan': 'plus',
              'fiveHourWindow': null,
              'sevenDayWindow': {'usedPercent': 54.0, 'resetsAt': '2026-08-30T00:00:00Z'},
              'source': 'Codex App Server / Local Sessions',
            },
            'antigravity': {
              'available': true,
              'model': 'gemini-3.7-flash-high',
              'status': 'Ready',
              'quota': '当前版本暂不可获取',
              'note': 'Antigravity CLI 本地接口当前不提供实时配额查询，按实际执行计费',
              'source': 'Antigravity CLI (Local)',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = BridgeMonitoringService(client: mockClient);

      await tester.pumpWidget(buildTestWidget(
        service: service,
        textScaleFactor: 1.3,
        size: const Size(360, 800), // Compact logical size
      ));
      await tester.pumpAndSettle();

      // Assert zero exceptions (no RenderFlex overflow)
      expect(tester.takeException(), isNull);
      expect(find.text('Mac 监控控制台'), findsOneWidget);
      expect(find.text('Mac 主机系统'), findsOneWidget);
      expect(find.text('Bridge 运行时与任务队列'), findsOneWidget);
      expect(find.text('Codex 引擎配额'), findsOneWidget);
      expect(find.text('Antigravity 引擎'), findsOneWidget);
      expect(find.text('当前版本暂不可获取'), findsOneWidget);
    });
  });
}
