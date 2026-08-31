import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/bridge_route_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'transport-only failover retains cached session and sends no task commands',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final first = 'ws://127.0.0.1:${server.port}';
      final second = 'ws://localhost:${server.port}';
      final sockets = <WebSocket>[];
      final commands = <String>[];
      var failed = false;
      final router = BridgeRouteSelector(
        probe: (url) async => failed && url == first
            ? null
            : {
                'status': 'ok',
                'network': {
                  'bridgeId': 'same-mac',
                  'endpoints': [first, second],
                },
              },
      );
      final bridge = BridgeService(routeSelector: router);
      server.transform(WebSocketTransformer()).listen((socket) {
        sockets.add(socket);
        socket.listen((raw) {
          commands.add((jsonDecode(raw as String) as Map)['type'] as String);
        });
        if (sockets.length == 1) {
          socket.add(
            jsonEncode({
              'type': 'assistant',
              'sessionId': 'stable-session',
              'message': {
                'id': 'a',
                'role': 'assistant',
                'content': [
                  {'type': 'text', 'text': 'retained output'},
                ],
              },
            }),
          );
          socket.add(
            jsonEncode({
              'type': 'project_history',
              'projects': ['/fixture/same-mac'],
            }),
          );
        }
      });
      try {
        bridge.connect(first);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await bridge.refreshRoutes();
        expect(router.sameServer(first, second), true);
        final cached = bridge.cachedSessionMessages('stable-session');
        expect(cached, isNotEmpty);
        failed = true;
        await bridge.refreshRoutes();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(bridge.lastUrl, second);
        expect(bridge.isConnected, true);
        expect(bridge.cachedSessionMessages('stable-session'), cached);
        expect(
          commands.where(
            (type) => ['input', 'start', 'resume_session'].contains(type),
          ),
          isEmpty,
        );
        expect(sockets, hasLength(2));
      } finally {
        bridge.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
}
