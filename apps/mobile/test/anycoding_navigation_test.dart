import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart' as provider_pkg;

import 'package:ccpocket/constants/brand_config.dart';
import 'package:ccpocket/features/anycoding/anycoding_main_screen.dart';
import 'package:ccpocket/features/anycoding/widgets/anycoding_bottom_navigation.dart';
import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/features/settings/state/settings_state.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/platform_environment_service.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccpocket/models/machine.dart';
import 'package:ccpocket/providers/machine_manager_cubit.dart';
import 'package:ccpocket/services/machine_manager_service.dart';

class _MockMachineManagerService implements MachineManagerService {
  final _controller = StreamController<List<MachineWithStatus>>.broadcast();

  @override
  Stream<List<MachineWithStatus>> get machines => _controller.stream;

  @override
  List<Machine> get currentMachines => const [];

  @override
  List<MachineWithStatus> get machinesWithStatus => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnyCoding 4-Tab Navigation & Shell Tests', () {
    Widget buildTestHarness(
      Widget child,
      SettingsCubit settingsCubit,
      MachineManagerCubit machineManagerCubit,
    ) {
      final bridge = BridgeService();

      return provider_pkg.MultiProvider(
        providers: [
          provider_pkg.Provider<BridgeService>.value(value: bridge),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<MachineManagerCubit>.value(value: machineManagerCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: child,
        ),
      );
    }

    testWidgets('renders 4 navigation tabs: 控制台, 任务, 项目, 设置', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final machineManagerService = _MockMachineManagerService();
      final machineManagerCubit = MachineManagerCubit(machineManagerService, null);
      final settingsCubit = SettingsCubit(prefs);

      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingMainScreen(
            connectionState: BridgeConnectionState.connected,
            connectedBridgeLabel: 'AnyCoding Mac',
            activeSessions: const [],
            recentSessions: const [],
            projectPaths: const {},
            onTapRunning: (_, {projectPath, gitBranch, worktreePath, provider, permissionMode, sandboxMode, approvalPolicy, approvalsReviewer}) {},
            onResumeRecentSession: (_) {},
            onArchiveSession: (_) {},
            onStopSession: (_) {},
            onRefresh: () {},
            onConnect: () {},
            onStartNewSession: (_) {},
          ),
          settingsCubit,
          machineManagerCubit,
        ),
      );

      expect(find.byType(AnyCodingBottomNavigation), findsOneWidget);
      expect(find.text('控制台'), findsOneWidget);
      expect(find.text('任务'), findsOneWidget);
      expect(find.text('项目'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('switching tabs switches view in IndexedStack and preserves page hierarchy', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final machineManagerService = _MockMachineManagerService();
      final machineManagerCubit = MachineManagerCubit(machineManagerService, null);
      final settingsCubit = SettingsCubit(prefs);

      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingMainScreen(
            connectionState: BridgeConnectionState.connected,
            connectedBridgeLabel: 'AnyCoding Mac',
            activeSessions: const [
              SessionInfo(
                id: 'active-1',
                provider: 'codex',
                projectPath: '/Users/test/workspace/repo-a',
                status: 'running',
                createdAt: '2026-08-24T00:00:00Z',
                lastActivityAt: '2026-08-24T00:00:00Z',
                lastMessage: 'Running unit test suite',
              ),
            ],
            recentSessions: const [],
            projectPaths: const {'/Users/test/workspace/repo-a'},
            onTapRunning: (_, {projectPath, gitBranch, worktreePath, provider, permissionMode, sandboxMode, approvalPolicy, approvalsReviewer}) {},
            onResumeRecentSession: (_) {},
            onArchiveSession: (_) {},
            onStopSession: (_) {},
            onRefresh: () {},
            onConnect: () {},
            onStartNewSession: (_) {},
          ),
          settingsCubit,
          machineManagerCubit,
        ),
      );

      // Default tab: 控制台 (Console)
      expect(find.text('新建 AI 任务'), findsOneWidget);
      expect(find.text('待处理事项'), findsOneWidget);

      // Switch to Tab 1: 任务 (Tasks)
      await tester.tap(find.text('任务'));
      await tester.pumpAndSettle();

      expect(find.text('任务中心'), findsOneWidget);
      expect(find.text('进行中'), findsWidgets);
      expect(find.text('已完成'), findsWidgets);

      // Switch to Tab 2: 项目 (Projects)
      await tester.tap(find.text('项目'));
      await tester.pumpAndSettle();

      expect(find.text('项目'), findsWidgets);
      expect(find.text('repo-a'), findsOneWidget);
      expect(find.text('启动 Codex'), findsOneWidget);
      expect(find.text('启动 Antigravity'), findsOneWidget);
    });
  });
}
