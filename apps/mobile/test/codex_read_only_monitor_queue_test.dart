import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider_pkg;

import 'package:ccpocket/features/anycoding/views/anycoding_tasks_view.dart';
import 'package:ccpocket/features/chat_session/state/streaming_state_cubit.dart';
import 'package:ccpocket/features/codex_session/state/codex_session_cubit.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';

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
  });
}
