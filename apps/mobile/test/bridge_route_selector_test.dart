import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccpocket/services/bridge_route_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lan = 'ws://192.168.1.10:8766';
  const ipv6 = 'ws://[2408::1]:8766';
  Map<String, dynamic> health([String id = 'mac-a']) => {
    'status': 'ok',
    'network': {
      'bridgeId': id,
      'endpoints': [lan, ipv6],
    },
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('discovers IPv6 while on LAN and excludes credentials', () async {
    final router = BridgeRouteSelector(
      probe: (url) async {
        expect(url.contains('token'), false);
        return health();
      },
    );
    await router.configure('$lan?token=private');
    await router.select('$lan?token=private', connected: true);
    expect(router.latency.keys, contains(ipv6));
    expect(router.sameServer(lan, ipv6), true);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('bridge_routes:${router.anchor}'),
      isNot(contains('private')),
    );
  });
  test('falls back using saved addresses when anchor is offline', () async {
    final first = BridgeRouteSelector(probe: (_) async => health());
    await first.configure(lan);
    await first.select(lan, connected: true);
    final next = BridgeRouteSelector(
      probe: (url) async => url == ipv6 ? health() : null,
    );
    await next.configure(lan);
    expect(await next.select(lan), ipv6);
    expect(next.sameServer(lan, ipv6), true);
  });
  test('rejects another server at a cached address', () async {
    final router = BridgeRouteSelector(
      probe: (url) async => health(url == ipv6 ? 'other' : 'mac-a'),
    );
    await router.configure(lan);
    expect(await router.select(lan), lan);
    expect(router.verified, isNot(contains(ipv6)));
  });
  test(
    'retains healthy connection while busy and prevents minor latency flapping',
    () async {
      final router = BridgeRouteSelector(probe: (_) async => health());
      await router.configure(lan);
      expect(await router.select(lan, connected: true, busy: true), lan);
      expect(await router.select(lan, connected: true), lan);
    },
  );
  test('does not apply late results after changing configured Mac', () async {
    final pending = Completer<Map<String, dynamic>?>();
    final router = BridgeRouteSelector(probe: (_) => pending.future);
    await router.configure(lan);
    final result = router.select(lan);
    await router.configure('ws://192.168.1.99:8766');
    pending.complete(health());
    expect(await result, lan);
    expect(router.verified, isEmpty);
    expect(router.latency.keys, isNot(contains(ipv6)));
  });
  test('legacy health keeps original route', () async {
    final router = BridgeRouteSelector(probe: (_) async => {'status': 'ok'});
    await router.configure(lan);
    expect(await router.select(lan), lan);
    expect(router.verified, isEmpty);
  });

  test('invalid input is not probed or persisted', () async {
    final router = BridgeRouteSelector(
      probe: (_) async => throw StateError('must not probe'),
    );
    await router.configure('ws://[');
    expect(await router.select('ws://['), 'ws://[');
    expect(router.latency, isEmpty);
  });

  test(
    'keeps established identity when DHCP assigns the anchor to another Mac',
    () async {
      var reassigned = false;
      final router = BridgeRouteSelector(
        probe: (url) async =>
            health(reassigned && url == lan ? 'mac-b' : 'mac-a'),
      );
      await router.configure(lan);
      await router.select(lan, connected: true);
      reassigned = true;
      expect(await router.select(ipv6, connected: true), ipv6);
      expect(router.bridgeId, 'mac-a');
      expect(router.latency[lan], isNull);
      expect(router.verified, isNot(contains(lan)));
      expect(router.sameServer(ipv6, lan), false);
    },
  );

  test(
    'new advertised addresses replace stale candidates within a bounded set',
    () async {
      var cycle = 0;
      final router = BridgeRouteSelector(
        probe: (url) async {
          if (url != lan && !url.contains('192.168.2.$cycle:')) return null;
          return {
            'status': 'ok',
            'network': {
              'bridgeId': 'mac-a',
              'endpoints': [lan, 'ws://192.168.2.$cycle:8766'],
            },
          };
        },
      );
      await router.configure(lan);
      for (cycle = 1; cycle < 20; cycle++) {
        await router.select(lan, connected: true);
        expect(router.latency.length, lessThanOrEqualTo(12));
        expect(router.latency['ws://192.168.2.$cycle:8766'], isNotNull);
        for (final entry in router.latency.entries) {
          if (entry.key != lan && entry.key != 'ws://192.168.2.$cycle:8766')
            expect(entry.value, isNull);
        }
      }
    },
  );
}
