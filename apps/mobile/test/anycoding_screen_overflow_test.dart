import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ccpocket/features/anycoding/views/anycoding_console_view.dart';
import 'package:ccpocket/features/anycoding/views/anycoding_projects_view.dart';
import 'package:ccpocket/features/anycoding/views/anycoding_tasks_view.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnyCoding Screen Overflow & Small Display Tests', () {
    Widget buildTestHarness(Widget child) {
      final bridge = BridgeService();
      return Provider<BridgeService>.value(
        value: bridge,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: child,
        ),
      );
    }

    testWidgets('Console view does not overflow on small screen (320x480)', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingConsoleView(
            connectionState: BridgeConnectionState.connected,
            connectedBridgeLabel: 'AnyCoding Mac',
            activeSessions: const [
              SessionInfo(
                id: 's1',
                provider: 'codex',
                projectPath: '/Users/test/workspace/my-extra-long-project-name-that-might-overflow',
                status: 'running',
                lastMessage: 'Running a long descriptive task command with extra details and parameters',
              ),
            ],
            recentSessions: const [],
            projectPaths: const {'/Users/test/workspace/my-extra-long-project-name-that-might-overflow'},
            onNewTask: () {},
            onTapRunning: (_, {projectPath, gitBranch, worktreePath, provider, permissionMode, sandboxMode, approvalPolicy, approvalsReviewer}) {},
            onResumeRecentSession: (_) {},
            onStopSession: (_) {},
            onRefresh: () {},
            onConnect: () {},
            bridge: BridgeService(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tasks view does not overflow on small screen with bottom keyboard inset', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestHarness(
          MediaQuery(
            data: const MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: 200),
            ),
            child: AnyCodingTasksView(
              activeSessions: const [
                SessionInfo(
                  id: 's1',
                  provider: 'antigravity',
                  projectPath: '/Users/test/workspace/app',
                  status: 'running',
                  lastMessage: 'Streaming agent steps...',
                ),
              ],
              recentSessions: const [],
              onNewTask: () {},
              onTapRunning: (_, {projectPath, gitBranch, worktreePath, provider, permissionMode, sandboxMode, approvalPolicy, approvalsReviewer}) {},
              onResumeRecentSession: (_) {},
              onArchiveSession: (_) {},
              onStopSession: (_) {},
              onRefresh: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
