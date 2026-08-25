import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccpocket/features/anycoding/services/task_status_classifier.dart';
import 'package:ccpocket/features/anycoding/views/anycoding_projects_view.dart';
import 'package:ccpocket/features/session_list/state/session_list_cubit.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnyCoding Project History Completeness Tests', () {
    final sixBridgePaths = [
      '/Users/developer/projects/alpha',
      '/Users/developer/projects/beta',
      '/Users/developer/projects/gamma',
      '/Users/developer/projects/delta',
      '/Users/developer/projects/epsilon',
      '/Users/developer/projects/zeta',
    ];

    final twoSessions = [
      const SessionInfo(
        id: 's1',
        provider: 'codex',
        projectPath: '/Users/developer/projects/alpha',
        status: 'running',
        createdAt: '2026-08-25T00:00:00Z',
        lastActivityAt: '2026-08-25T00:00:00Z',
      ),
      const RecentSession(
        sessionId: 'r1',
        provider: 'codex',
        firstPrompt: 'fix beta issue',
        created: '2026-08-25T00:00:00Z',
        modified: '2026-08-25T00:10:00Z',
        gitBranch: 'main',
        projectPath: '/Users/developer/projects/beta',
        isSidechain: false,
      ),
    ];

    test('TaskStatusClassifier.buildProjectSummaries merges 6 bridge history paths with 2 sessions to produce 6 projects', () {
      final allTasks = TaskStatusClassifier.buildUnifiedTaskList(
        activeSessions: [twoSessions[0] as SessionInfo],
        recentSessions: [twoSessions[1] as RecentSession],
      );

      final summaries = TaskStatusClassifier.buildProjectSummaries(
        allTasks: allTasks,
        projectPaths: {'/Users/developer/projects/alpha'},
        bridgeProjectHistory: sixBridgePaths,
      );

      expect(summaries.length, equals(6));
      final names = summaries.map((s) => s.name).toSet();
      expect(names, containsAll({'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'}));

      // Normalization check: trailing slash or duplicate path format should be deduplicated
      final summariesWithDups = TaskStatusClassifier.buildProjectSummaries(
        allTasks: allTasks,
        projectPaths: {
          '/Users/developer/projects/alpha',
          '/Users/developer/projects/alpha/',
          '\\Users\\developer\\projects\\alpha',
        },
        bridgeProjectHistory: [
          ...sixBridgePaths,
          '/Users/developer/projects/beta/',
        ],
      );
      expect(summariesWithDups.length, equals(6));
    });

    test('SessionListCubit seeds and merges project history correctly', () async {
      final bridge = BridgeService();
      bridge.testHandleMessage(
        ProjectHistoryMessage(projects: sixBridgePaths),
      );

      final cubit = SessionListCubit(bridge: bridge);
      expect(cubit.state.accumulatedProjectPaths.length, equals(6));

      // Test new project history broadcast
      bridge.testHandleMessage(
        const ProjectHistoryMessage(projects: [
          '/Users/developer/projects/eta',
          '/Users/developer/projects/alpha',
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.accumulatedProjectPaths.length, equals(7));
      await cubit.close();
    });

    testWidgets('AnyCodingProjectsView displays all 6 projects when Bridge has 6 history paths and sessions only have 2', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();

      await tester.pumpWidget(
        provider_pkg.Provider<BridgeService>.value(
          value: bridge,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: AnyCodingProjectsView(
              activeSessions: [twoSessions[0] as SessionInfo],
              recentSessions: [twoSessions[1] as RecentSession],
              projectPaths: const {'/Users/developer/projects/alpha'},
              bridge: bridge,
              onLaunchProject: (_, __) {},
              onSelectProject: (_) {},
            ),
          ),
        ),
      );

      // Initially with empty bridge.projectHistory, shows alpha and beta
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);

      // Now bridge receives project_history with 6 paths
      bridge.testHandleMessage(
        ProjectHistoryMessage(projects: sixBridgePaths),
      );
      await tester.pumpAndSettle();

      // All 6 projects should now be rendered
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget);
      expect(find.text('delta'), findsOneWidget);
      expect(find.text('epsilon'), findsOneWidget);
      expect(find.text('zeta'), findsOneWidget);
    });
  });
}
