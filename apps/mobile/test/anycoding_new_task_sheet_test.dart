import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider_pkg;

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
      return provider_pkg.Provider<BridgeService>.value(
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

    testWidgets('submits NewSessionParams with initialPrompt when prompt is entered', (tester) async {
      NewSessionParams? resultParams;

      await tester.pumpWidget(
        buildTestHarness(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  resultParams = await showModalBottomSheet<NewSessionParams>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AnyCodingNewTaskSheet(
                      recentProjects: const [
                        (path: '/Users/test/workspace/my-app', name: 'my-app'),
                      ],
                      bridge: BridgeService(),
                      initialProjectPath: '/Users/test/workspace/my-app',
                      initialProvider: Provider.codex,
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Enter prompt
      final promptField = find.byType(TextField);
      expect(promptField, findsOneWidget);
      await tester.enterText(promptField, 'ANYCODING_PHASE1_CODEX_E2E_read_package_json');
      await tester.pumpAndSettle();

      // Tap launch button
      await tester.tap(find.byKey(const ValueKey('anycoding_launch_task_button')));
      await tester.pumpAndSettle();

      expect(resultParams, isNotNull);
      expect(resultParams!.projectPath, '/Users/test/workspace/my-app');
      expect(resultParams!.provider, Provider.codex);
      expect(resultParams!.initialPrompt, 'ANYCODING_PHASE1_CODEX_E2E_read_package_json');
    });
  });
}
