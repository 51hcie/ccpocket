import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider_pkg;

import 'package:ccpocket/features/anycoding/views/anycoding_projects_view.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnyCoding Projects Tab Tests', () {
    Widget buildTestHarness(Widget child) {
      final bridge = BridgeService();
      return provider_pkg.Provider<BridgeService>.value(
        value: bridge,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: child,
        ),
      );
    }

    testWidgets('renders projects with directory name and both launch buttons', (tester) async {
      String? launchedPath;
      Provider? launchedProvider;

      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingProjectsView(
            activeSessions: const [
              SessionInfo(
                id: 's1',
                provider: 'codex',
                projectPath: '/Users/developer/projects/antigravity-hub',
                status: 'running',
                createdAt: '2026-08-24T00:00:00Z',
                lastActivityAt: '2026-08-24T00:00:00Z',
              ),
            ],
            recentSessions: const [
              RecentSession(
                sessionId: 'r1',
                provider: 'antigravity',
                firstPrompt: 'Refactor parser',
                created: '2026-08-24T00:00:00Z',
                modified: '2026-08-24T00:30:00Z',
                gitBranch: 'main',
                projectPath: '/Users/developer/projects/antigravity-hub',
                isSidechain: false,
              ),
            ],
            projectPaths: const {'/Users/developer/projects/antigravity-hub'},
            bridge: BridgeService(),
            onLaunchProject: (path, provider) {
              launchedPath = path;
              launchedProvider = provider;
            },
            onSelectProject: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Primary project directory name
      expect(find.text('antigravity-hub'), findsOneWidget);

      // Launch buttons
      expect(find.text('启动 Codex'), findsOneWidget);
      expect(find.text('启动 Antigravity'), findsOneWidget);

      // Tap launch Codex
      await tester.tap(find.text('启动 Codex'));
      await tester.pumpAndSettle();
      expect(launchedPath, equals('/Users/developer/projects/antigravity-hub'));
      expect(launchedProvider, equals(Provider.codex));

      // Tap launch Antigravity
      await tester.tap(find.text('启动 Antigravity'));
      await tester.pumpAndSettle();
      expect(launchedProvider, equals(Provider.antigravity));
    });
  });
}
