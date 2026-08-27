import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccpocket/features/anycoding/views/anycoding_tasks_view.dart';
import 'package:ccpocket/features/chat_session/state/chat_session_cubit.dart';
import 'package:ccpocket/features/chat_session/state/streaming_state_cubit.dart';
import 'package:ccpocket/features/codex_session/codex_session_screen.dart';
import 'package:ccpocket/features/codex_session/state/codex_session_cubit.dart';
import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/database_service.dart';
import 'package:ccpocket/services/draft_service.dart';
import 'package:ccpocket/services/prompt_history_service.dart';
import 'package:ccpocket/theme/app_theme.dart';

Future<Widget> buildTestCodexScreenHarness({
  required BridgeService bridge,
  required Widget child,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    theme: AppTheme.darkTheme,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<BridgeService>.value(value: bridge),
        RepositoryProvider<DraftService>.value(value: DraftService(prefs)),
        RepositoryProvider<PromptHistoryService>.value(
          value: PromptHistoryService(DatabaseService()),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ConnectionCubit>(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              bridge.connectionStatus,
            ),
          ),
          BlocProvider<FileListCubit>(
            create: (_) => FileListCubit(const <String>[], bridge.fileList),
          ),
          BlocProvider<SettingsCubit>(create: (_) => SettingsCubit(prefs)),
        ],
        child: child,
      ),
    ),
  );
}

Future<void> pumpN(WidgetTester tester, {int count = 5}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestHarness(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    );
  }

  group('Codex Read-Only Monitor and Takeover Queue Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Tapping historical Codex task in AnyCodingTasksView (completed tab) defaults to read-only monitor without calling onResumeRecentSession', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      RecentSession? resumedSession;
      String? openedRunningId;
      String? openedProvider;

      const codexRecent = RecentSession(
        sessionId: 'codex-hist-1',
        provider: 'codex',
        firstPrompt: 'Investigate deadlock',
        created: '2026-08-25T00:00:00Z',
        modified: '2026-08-25T00:30:00Z',
        gitBranch: 'main',
        projectPath: '/Users/developer/projects/anycoding',
        isSidechain: false,
      );

      await tester.pumpWidget(
        buildTestHarness(
          AnyCodingTasksView(
            activeSessions: const [],
            recentSessions: const [codexRecent],
            pinnedKeys: const {},
            onNewTask: () {},
            onTapRunning: (sessionId, {projectPath, gitBranch, worktreePath, provider, permissionMode, sandboxMode, approvalPolicy, approvalsReviewer}) {
              openedRunningId = sessionId;
              openedProvider = provider;
            },
            onResumeRecentSession: (session) {
              resumedSession = session;
            },
            onArchiveSession: (_) {},
            onStopSession: (_) {},
            onRefresh: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "已完成" (completed) tab
      await tester.tap(find.text('已完成'));
      await tester.pumpAndSettle();

      // Tap the recent task item
      expect(find.text('Investigate deadlock'), findsOneWidget);
      await tester.tap(find.text('Investigate deadlock'));
      await tester.pumpAndSettle();

      // Must route to onTapRunning (read-only monitor mode) and NOT call onResumeRecentSession
      expect(openedRunningId, equals('codex-hist-1'));
      expect(openedProvider, equals(Provider.codex.value));
      expect(resumedSession, isNull);
    });

    test('CodexTakeoverConflictMessage and Bridge stream receive conflict events', () async {
      final bridge = BridgeService();
      CodexTakeoverConflictMessage? receivedConflict;

      final sub = bridge.codexTakeoverConflictStream.listen((msg) {
        receivedConflict = msg;
      });

      bridge.testHandleMessage(
        const CodexTakeoverConflictMessage(
          threadId: 'sess-conflict-1',
          projectPath: '/Users/developer/projects/anycoding',
          message: 'Thread is running with an active writer in another window',
          canQueue: true,
          queueLength: 2,
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(receivedConflict, isNotNull);
      expect(receivedConflict!.threadId, equals('sess-conflict-1'));
      expect(receivedConflict!.canQueue, isTrue);
      expect(receivedConflict!.queueLength, equals(2));
      await sub.cancel();
    });

    test('CodexTakeoverQueueStatusMessage and Bridge stream receive queue events', () async {
      final bridge = BridgeService();
      CodexTakeoverQueueStatusMessage? receivedStatus;

      final sub = bridge.codexTakeoverQueueStatusStream.listen((msg) {
        receivedStatus = msg;
      });

      bridge.testHandleMessage(
        const CodexTakeoverQueueStatusMessage(
          threadId: 'sess-queue-1',
          queueId: 'q-99',
          position: 1,
          total: 3,
          status: 'queued',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(receivedStatus, isNotNull);
      expect(receivedStatus!.threadId, equals('sess-queue-1'));
      expect(receivedStatus!.position, equals(1));
      expect(receivedStatus!.total, equals(3));
      expect(receivedStatus!.isQueued, isTrue);
      await sub.cancel();
    });

    test('CodexReadOnlyInfoMessage and Bridge stream receive read-only info events', () async {
      final bridge = BridgeService();
      CodexReadOnlyInfoMessage? receivedInfo;

      final sub = bridge.codexReadOnlyInfoStream.listen((msg) {
        receivedInfo = msg;
      });

      bridge.testHandleMessage(
        const CodexReadOnlyInfoMessage(
          threadId: 'sess-ro-1',
          isReadOnly: true,
          isLocalHistory: true,
          status: 'completed',
          updatedAt: '2026-08-25T01:00:00Z',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(receivedInfo, isNotNull);
      expect(receivedInfo!.threadId, equals('sess-ro-1'));
      expect(receivedInfo!.isReadOnly, isTrue);
      expect(receivedInfo!.isLocalHistory, isTrue);
      expect(receivedInfo!.status, equals('completed'));
      await sub.cancel();
    });

    test('ClientMessage factories for takeover queue generate correct JSON', () {
      final enqueueMsg = ClientMessage.enqueueCodexTakeover(
        threadId: 'sess-1',
        projectPath: '/test/path',
        queuedCommand: 'do something',
      );
      final enqueueJson = jsonDecode(enqueueMsg.toJson()) as Map<String, dynamic>;
      expect(enqueueJson['type'], equals('enqueue_codex_takeover'));
      expect(enqueueJson['threadId'], equals('sess-1'));
      expect(enqueueJson['queuedCommand'], equals('do something'));

      final cancelMsg = ClientMessage.cancelCodexTakeover(
        threadId: 'sess-1',
        queueId: 'q-100',
      );
      final cancelJson = jsonDecode(cancelMsg.toJson()) as Map<String, dynamic>;
      expect(cancelJson['type'], equals('cancel_codex_takeover'));
      expect(cancelJson['queueId'], equals('q-100'));

      final getQueueMsg = ClientMessage.getCodexTakeoverQueue(
        threadId: 'sess-1',
      );
      final getQueueJson = jsonDecode(getQueueMsg.toJson()) as Map<String, dynamic>;
      expect(getQueueJson['type'], equals('get_codex_takeover_queue'));
    });

    test('CodexSessionCubit in read-only mode triggers resume on send, and sends command once on session_created', () async {
      final bridge = BridgeService();
      final streamingCubit = StreamingStateCubit();
      final sentClientMessages = <ClientMessage>[];
      bridge.onOutgoingMessage = (msg) => sentClientMessages.add(msg);

      final cubit = CodexSessionCubit(
        sessionId: 'thread-test-1',
        bridge: bridge,
        streamingCubit: streamingCubit,
        initialProjectPath: '/repo',
        isReadOnly: true,
      );

      expect(cubit.isReadOnlySession, isTrue);

      // User sends a message in read-only mode
      cubit.sendMessage('Refactor module');

      // 1. Must NOT send input directly to non-existent session!
      // Must trigger resumeSession instead.
      final resumeMsgs = sentClientMessages.where(
        (m) =>
            m.toJson().contains('resume_session') &&
            m.toJson().contains('thread-test-1'),
      );
      expect(resumeMsgs, isNotEmpty);
      expect(cubit.hasPendingResumeCommand, isTrue);

      final inputBeforeResume = sentClientMessages.where(
        (m) =>
            m.toJson().contains('"type":"input"') &&
            m.toJson().contains('Refactor module'),
      );
      expect(inputBeforeResume, isEmpty);

      // 2. Simulate session_created arriving from bridge
      bridge.testHandleMessage(
        const SystemMessage(
          subtype: 'session_created',
          sourceSessionId: 'thread-test-1',
          sessionId: 'thread-test-1',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      // 3. Now the pending command should have been dispatched EXACTLY ONCE
      final inputAfterResume = sentClientMessages.where(
        (m) =>
            m.toJson().contains('"type":"input"') &&
            m.toJson().contains('Refactor module'),
      );
      expect(inputAfterResume.length, equals(1));
      expect(cubit.hasPendingResumeCommand, isFalse);

      await cubit.close();
      await streamingCubit.close();
    });

    test('CodexSessionCubit enqueues command to takeover queue upon conflict', () async {
      final bridge = BridgeService();
      final streamingCubit = StreamingStateCubit();
      final sentClientMessages = <ClientMessage>[];
      bridge.onOutgoingMessage = (msg) => sentClientMessages.add(msg);

      final cubit = CodexSessionCubit(
        sessionId: 'thread-conflict-1',
        bridge: bridge,
        streamingCubit: streamingCubit,
        initialProjectPath: '/repo',
        isReadOnly: true,
      );

      // User sends message
      cubit.sendMessage('Fix deadlock bug');

      // Bridge returns active writer conflict
      bridge.testHandleMessage(
        const CodexTakeoverConflictMessage(
          threadId: 'thread-conflict-1',
          projectPath: '/repo',
          message: 'active writer conflict',
          canQueue: true,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      // Command must be queued to takeover queue without being lost
      final enqueueMsgs = sentClientMessages.where(
        (m) =>
            m.toJson().contains('enqueue_codex_takeover') &&
            m.toJson().contains('Fix deadlock bug'),
      );
      expect(enqueueMsgs.length, equals(1));
      expect(cubit.hasPendingResumeCommand, isFalse);

      await cubit.close();
      await streamingCubit.close();
    });

    test('CodexSessionCubit takeControl triggers resume with or without command', () async {
      final bridge = BridgeService();
      final streamingCubit = StreamingStateCubit();
      final sentClientMessages = <ClientMessage>[];
      bridge.onOutgoingMessage = (msg) => sentClientMessages.add(msg);

      final cubit = CodexSessionCubit(
        sessionId: 'thread-takecontrol-1',
        bridge: bridge,
        streamingCubit: streamingCubit,
        initialProjectPath: '/repo',
        isReadOnly: true,
      );

      // 1. takeControl without command -> resumes session directly
      cubit.takeControl();
      final resumeMsgs = sentClientMessages.where(
        (m) =>
            m.toJson().contains('resume_session') &&
            m.toJson().contains('thread-takecontrol-1'),
      );
      expect(resumeMsgs.length, equals(1));
      expect(cubit.hasPendingResumeCommand, isFalse);

      // 2. takeControl with command -> resume-then-send flow
      cubit.takeControl(command: 'Run migration');
      expect(cubit.hasPendingResumeCommand, isTrue);

      await cubit.close();
      await streamingCubit.close();
    });

    testWidgets('CodexSessionScreen for inactive historical session displays read-only banner, refresh, and enter control without showing session unavailable, and shows messages on history arrival', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();
      final sentClientMessages = <ClientMessage>[];
      bridge.onOutgoingMessage = (msg) => sentClientMessages.add(msg);

      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'hist-codex-1',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      // 1. Initial active session does not exist in bridge.sessions.
      // Must display read-only monitor banner, refresh, and enter control; must NOT show session unavailable.
      expect(find.byKey(const ValueKey('codex_read_only_monitor_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('codex_read_only_refresh_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('codex_read_only_take_control_button')), findsOneWidget);
      expect(find.text('进入控制'), findsOneWidget);
      expect(find.text('会话不可用'), findsNothing);

      // 2. Tapping refresh triggers get_history
      await tester.tap(find.byKey(const ValueKey('codex_read_only_refresh_button')));
      await pumpN(tester);
      expect(
        sentClientMessages.any((m) => m.toJson().contains('get_history') && m.toJson().contains('hist-codex-1')),
        isTrue,
      );

      // 3. CodexReadOnlyInfo arrives from Bridge
      bridge.testHandleMessage(
        const CodexReadOnlyInfoMessage(
          threadId: 'hist-codex-1',
          isReadOnly: true,
          isLocalHistory: true,
          status: 'completed',
          updatedAt: '2026-08-25T11:00:00Z',
        ),
        sessionId: 'hist-codex-1',
      );
      await pumpN(tester);

      expect(find.text('本地历史记录 (只读)'), findsOneWidget);
      expect(find.text('会话不可用'), findsNothing);

      // 4. History arrives from Bridge with assistant message
      bridge.testHandleMessage(
        const HistoryMessage(
          messages: [
            AssistantServerMessage(
              message: AssistantMessage(
                id: 'msg-1',
                role: 'assistant',
                content: [TextContent(text: 'Historical code inspection complete.')],
                model: 'gpt-4o',
              ),
            ),
          ],
        ),
        sessionId: 'hist-codex-1',
      );
      await pumpN(tester);

      // Content must be displayed and session unavailable still NOT shown
      expect(find.text('Historical code inspection complete.'), findsOneWidget);
      expect(find.text('会话不可用'), findsNothing);
      expect(find.byKey(const ValueKey('codex_read_only_monitor_banner')), findsOneWidget);

      // 5. Tapping take control triggers resume session
      await tester.tap(find.byKey(const ValueKey('codex_read_only_take_control_button')));
      await pumpN(tester);
      expect(
        sentClientMessages.any((m) => m.toJson().contains('resume_session') && m.toJson().contains('hist-codex-1')),
        isTrue,
      );
    });

    testWidgets('CodexSessionScreen displays SessionUnavailableView when bridge explicitly returns session_not_found and no history exists', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();

      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'missing-codex-thread',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      // Simulate bridge returning explicit session_not_found error
      bridge.testHandleMessage(
        const ErrorMessage(
          message: 'Session missing-codex-thread not found',
          errorCode: 'session_not_found',
          sessionId: 'missing-codex-thread',
        ),
        sessionId: 'missing-codex-thread',
      );
      await pumpN(tester);

      // Must show session unavailable view
      expect(find.text('会话不可用'), findsOneWidget);
      expect(find.byKey(const ValueKey('codex_read_only_monitor_banner')), findsNothing);
    });

    testWidgets('CodexSessionScreen on active writer conflict stays on read-only page and does not show session unavailable', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();

      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'conflict-codex-thread',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      // Simulate bridge emitting conflict message
      bridge.testHandleMessage(
        const CodexTakeoverConflictMessage(
          threadId: 'conflict-codex-thread',
          projectPath: '/workspace',
          message: 'Thread is running with an active writer in another window',
          canQueue: true,
          queueLength: 1,
        ),
        sessionId: 'conflict-codex-thread',
      );
      await pumpN(tester);

      // Must NOT show SessionUnavailableView
      expect(find.text('会话不可用'), findsNothing);
      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
    });

    test('CodexSessionCubit clears sessionUnavailable state when CodexReadOnlyInfo / History / Conflict arrives', () async {
      final bridge = BridgeService();
      final streamingCubit = StreamingStateCubit();

      final cubit = CodexSessionCubit(
        sessionId: 'test-recovery-thread',
        bridge: bridge,
        streamingCubit: streamingCubit,
        initialProjectPath: '/repo',
        isReadOnly: true,
      );

      // Force sessionUnavailable to true (e.g. from early session_not_found error)
      cubit.emit(cubit.state.copyWith(sessionUnavailable: true));
      expect(cubit.state.sessionUnavailable, isTrue);

      // 1. CodexReadOnlyInfo arrives -> clears sessionUnavailable
      bridge.testHandleMessage(
        const CodexReadOnlyInfoMessage(
          threadId: 'test-recovery-thread',
          isReadOnly: true,
          status: 'idle',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.sessionUnavailable, isFalse);

      // Set to true again
      cubit.emit(cubit.state.copyWith(sessionUnavailable: true));
      expect(cubit.state.sessionUnavailable, isTrue);

      // 2. Conflict arrives -> clears sessionUnavailable
      bridge.testHandleMessage(
        const CodexTakeoverConflictMessage(
          threadId: 'test-recovery-thread',
          projectPath: '/repo',
          message: 'conflict',
          canQueue: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.sessionUnavailable, isFalse);

      // Set to true again
      cubit.emit(cubit.state.copyWith(sessionUnavailable: true));
      expect(cubit.state.sessionUnavailable, isTrue);

      // 3. HistoryMessage arrives -> clears sessionUnavailable
      bridge.testHandleMessage(
        const HistoryMessage(
          messages: [
            AssistantServerMessage(
              message: AssistantMessage(
                id: 'm1',
                role: 'assistant',
                content: [TextContent(text: 'Ready')],
                model: 'gpt-4o',
              ),
            ),
          ],
        ),
        sessionId: 'test-recovery-thread',
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.sessionUnavailable, isFalse);

      await cubit.close();
      await streamingCubit.close();
    });

    testWidgets('CodexSessionScreen renders queued -> running -> completed states maintaining same queueId', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();
      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'thread-lifecycle-ui',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      // 1. Queued state
      bridge.testHandleMessage(
        const CodexTakeoverQueueStatusMessage(
          threadId: 'thread-lifecycle-ui',
          queueId: 'q-ui-1234',
          position: 1,
          total: 1,
          status: 'queued',
        ),
        sessionId: 'thread-lifecycle-ui',
      );
      await pumpN(tester);

      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
      expect(find.text('Codex 活跃写入者冲突'), findsOneWidget);
      expect(find.textContaining('排队中: 第 1 / 1 位 (Queue ID: q-ui-1234)'), findsOneWidget);
      expect(find.byKey(const ValueKey('codex_conflict_cancel_queue_button')), findsOneWidget);

      // 2. Running / Resumed state
      bridge.testHandleMessage(
        const CodexTakeoverQueueStatusMessage(
          threadId: 'thread-lifecycle-ui',
          queueId: 'q-ui-1234',
          position: 0,
          total: 0,
          status: 'running',
        ),
        sessionId: 'thread-lifecycle-ui',
      );
      await pumpN(tester);

      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
      expect(find.text('Codex 接管执行中'), findsOneWidget);
      expect(find.textContaining('执行中 (Queue ID: q-ui-1234)'), findsOneWidget);

      // 3. Completed state
      bridge.testHandleMessage(
        const CodexTakeoverQueueStatusMessage(
          threadId: 'thread-lifecycle-ui',
          queueId: 'q-ui-1234',
          position: 0,
          total: 0,
          status: 'completed',
        ),
        sessionId: 'thread-lifecycle-ui',
      );
      await pumpN(tester);

      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
      expect(find.text('Codex 接管已完成'), findsOneWidget);
      expect(find.textContaining('已完成 (Queue ID: q-ui-1234)'), findsOneWidget);
    });

    testWidgets('CodexSessionScreen restores queued state and queueId from SharedPreferences on restart', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();
      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        initialPrefs: {
          'codex_takeover_queue_thread-persisted-restore': 'q-restored-888',
        },
        child: const CodexSessionScreen(
          sessionId: 'thread-persisted-restore',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      // The banner should be restored from SharedPreferences immediately with queueId
      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
      expect(find.text('排队中: 第 1 / 1 位 (Queue ID: q-restored-888)'), findsOneWidget);
    });

    testWidgets('Active writer conflict ErrorMessage is suppressed from chat message list in CodexSessionScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bridge = BridgeService();
      final harness = await buildTestCodexScreenHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'thread-no-error-card',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(harness);
      await pumpN(tester);

      bridge.testHandleMessage(
        const ErrorMessage(
          message: 'This Codex thread is already open in another client. Close it there and try again.',
          errorCode: 'active_writer_conflict',
          sessionId: 'thread-no-error-card',
        ),
        sessionId: 'thread-no-error-card',
      );
      await pumpN(tester);

      // The conflict banner should be shown
      expect(find.byKey(const ValueKey('codex_takeover_conflict_banner')), findsOneWidget);
      // But NO error message card containing 'already open in another client' should exist in the chat message list
      expect(find.textContaining('This Codex thread is already open in another client'), findsNothing);
    });
  });
}
