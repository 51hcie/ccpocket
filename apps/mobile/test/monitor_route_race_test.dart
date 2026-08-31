import 'dart:async';

import 'package:ccpocket/features/anycoding/views/anycoding_monitoring_view.dart';
import 'package:ccpocket/services/bridge_monitoring_service.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RouteBridge extends BridgeService {
  String url = 'ws://old:8766';
  final changes = StreamController<void>.broadcast();
  @override
  String? get lastUrl => url;
  @override
  Stream<void> get routeChanges => changes.stream;
  void change(String next) {
    url = next;
    changes.add(null);
  }

  @override
  void dispose() {
    changes.close();
    super.dispose();
  }
}

class DeferredMonitor extends BridgeMonitoringService {
  final requests = <Completer<MonitoringDataModel>>[];
  @override
  Future<MonitoringDataModel> fetchMonitoringData(String url) {
    final request = Completer<MonitoringDataModel>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('failed refresh labels cached data and recovery clears notice', (
    tester,
  ) async {
    final bridge = RouteBridge();
    final monitor = DeferredMonitor();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnyCodingMonitoringSheet(
            bridge: bridge,
            monitoringService: monitor,
          ),
        ),
      ),
    );
    monitor.requests[0].complete(MonitoringDataModel.fromJson({}));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    monitor.requests[1].completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('monitor_stale_data_notice')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 8));
    monitor.requests[2].complete(MonitoringDataModel.fromJson({}));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('monitor_stale_data_notice')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    bridge.dispose();
  });
  for (final oldFails in [false, true]) {
    testWidgets(
      'old route ${oldFails ? "error" : "response"} cannot overwrite new route',
      (tester) async {
        final bridge = RouteBridge();
        final monitor = DeferredMonitor();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnyCodingMonitoringSheet(
                bridge: bridge,
                monitoringService: monitor,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 8));
        expect(
          monitor.requests.length,
          1,
        ); // Slow same-route requests do not overlap.
        bridge.change('ws://new:8766');
        await tester.pump();
        expect(monitor.requests.length, 2);
        monitor.requests[1].completeError(Exception('new route diagnostic'));
        await tester.pump();
        expect(find.text('new route diagnostic'), findsOneWidget);
        if (oldFails) {
          monitor.requests[0].completeError(Exception('old route diagnostic'));
        } else {
          monitor.requests[0].complete(MonitoringDataModel.fromJson({}));
        }
        await tester.pump();
        expect(find.text('new route diagnostic'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        bridge.dispose();
      },
    );
  }
}
