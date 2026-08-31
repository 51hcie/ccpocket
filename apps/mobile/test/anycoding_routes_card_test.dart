import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/features/anycoding/widgets/anycoding_routes_card.dart';

void main() {
  testWidgets(
    'shows both addresses without overflow on a narrow large-text screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bridge = BridgeService();
      bridge.routes.latency['ws://192.168.31.247:8766'] = 12;
      bridge
              .routes
              .latency['ws://[2408:824e:1580:9c80:61a6:113b:9bc5:abe4]:8766'] =
          80;
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: AnyCodingRoutesCard(bridge: bridge),
              ),
            ),
          ),
        ),
      );
      expect(find.text('IPv6 地址 · 80 ms'), findsOneWidget);
      expect(find.textContaining('12 ms'), findsOneWidget);
      expect(find.byTooltip('复制地址'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      bridge.dispose();
    },
  );
}
