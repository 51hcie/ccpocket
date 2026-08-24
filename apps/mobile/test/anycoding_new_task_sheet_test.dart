import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ccpocket/features/anycoding/widgets/anycoding_new_task_sheet.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/widgets/new_session_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnyCoding New Task Sheet Flow Tests', () {
    Widget buildTestHarness(Widget child) {
      final bridge = BridgeService();
      return Provider<BridgeService>.value(
        value: bridge,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('renders 4-step flow: Select Project, Select Engine, Input Prompt, Launch', (tester) async {
      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingNewTaskSheet(
            recentProjects: const [
              (path: '/Users/test/workspace/my-app', name: 'my-app'),
            ],
            bridge: BridgeService(),
            initialProjectPath: '/Users/test/workspace/my-app',
          ),
        ),
      );

      // Steps
      expect(find.text('选择项目'), findsOneWidget);
      expect(find.text('选择执行引擎'), findsOneWidget);
      expect(find.text('输入初始指令'), findsOneWidget);
      expect(find.text('高级选项'), findsOneWidget);

      // Engines (Codex & Antigravity only, no Claude)
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Antigravity'), findsOneWidget);
      expect(find.text('Claude'), findsNothing);

      // Launch button
      expect(find.byKey(const ValueKey('anycoding_launch_task_button')), findsOneWidget);
    });

    testWidgets('toggling engine updates the launch button label', (tester) async {
      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingNewTaskSheet(
            recentProjects: const [
              (path: '/Users/test/workspace/my-app', name: 'my-app'),
            ],
            bridge: BridgeService(),
            initialProjectPath: '/Users/test/workspace/my-app',
            initialProvider: Provider.codex,
          ),
        ),
      );

      expect(find.text('启动 Codex 任务'), findsOneWidget);

      // Tap Antigravity engine card
      await tester.tap(find.text('Antigravity'));
      await tester.pumpAndSettle();

      expect(find.text('启动 Antigravity 任务'), findsOneWidget);
    });
  });
}
