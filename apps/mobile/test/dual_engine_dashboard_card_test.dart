import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccpocket/features/session_list/widgets/dual_engine_dashboard_card.dart';
import 'package:ccpocket/models/messages.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('DualEngineDashboardCard UI Tests (Task 1 & Task 2)', () {
    testWidgets(
        'renders Offline status for engines when Bridge is disconnected', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const DualEngineDashboardCard(
            connectionState: BridgeConnectionState.disconnected,
            endpointLabel: '[2408:824e:158d:5a80:875:122:45bf:5441]:8766',
            runningCount: 0,
            waitingCount: 0,
            failedCount: 0,
            completedCount: 0,
            codexStatusLabel: 'Offline',
            antigravityStatusLabel: 'Offline',
            isCodexOnline: false,
            isAntigravityOnline: false,
          ),
        ),
      );

      expect(find.text('Mac Bridge Offline'), findsOneWidget);
      expect(find.text('Codex: Offline'), findsOneWidget);
      expect(find.text('Antigravity: Offline'), findsOneWidget);
      expect(
        find.text('[2408:824e:158d:5a80:875:122:45bf:5441]:8766'),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders Ready for Codex and Supported for Antigravity when connected',
      (tester) async {
        await tester.pumpWidget(
          buildTestableWidget(
            const DualEngineDashboardCard(
              connectionState: BridgeConnectionState.connected,
              endpointLabel: 'ws://127.0.0.1:8766',
              runningCount: 3,
              waitingCount: 1,
              failedCount: 2,
              completedCount: 5,
              codexStatusLabel: 'Ready',
              antigravityStatusLabel: 'Supported',
              isCodexOnline: true,
              isAntigravityOnline: true,
            ),
          ),
        );

        expect(find.text('Mac Bridge Online'), findsOneWidget);
        expect(find.text('Codex: Ready'), findsOneWidget);
        expect(find.text('Antigravity: Supported'), findsOneWidget);

        // Verify 4 Metric Chips
        expect(find.text('Running'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);

        expect(find.text('Waiting'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        expect(find.text('Failed'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        expect(find.text('Done'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
      },
    );
  });
}
