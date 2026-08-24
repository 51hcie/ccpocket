import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ccpocket/features/claude_session/claude_session_screen.dart';
import 'package:ccpocket/features/codex_session/codex_session_screen.dart';
import 'package:ccpocket/features/chat_session/state/chat_session_cubit.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/database_service.dart';
import 'package:ccpocket/services/draft_service.dart';
import 'package:ccpocket/services/prompt_history_service.dart';
import 'package:ccpocket/features/settings/state/settings_cubit.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/theme/app_theme.dart';

class MockTestBridgeService extends BridgeService {
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _taggedController = StreamController<(ServerMessage, String?)>.broadcast();
  final _connectionController = StreamController<BridgeConnectionState>.broadcast();
  final _fileListController = StreamController<List<String>>.broadcast();
  final _sessionListController = StreamController<List<SessionInfo>>.broadcast();
  final sentMessages = <ClientMessage>[];

  void emitMessage(ServerMessage msg, {String? sessionId}) {
    _taggedController.add((msg, sessionId));
    _messageController.add(msg);
  }

  @override
  Stream<ServerMessage> get messages => _messageController.stream;

  @override
  Stream<BridgeConnectionState> get connectionStatus => _connectionController.stream;

  @override
  Stream<List<String>> get fileList => _fileListController.stream;

  @override
  Stream<List<SessionInfo>> get sessionList => _sessionListController.stream;

  @override
  bool get isConnected => true;

  @override
  Stream<ServerMessage> messagesForSession(String sessionId) {
    return _taggedController.stream
        .where((pair) => pair.$2 == null || pair.$2 == sessionId)
        .map((pair) => pair.$1);
  }

  @override
  void send(ClientMessage message) {
    sentMessages.add(message);
  }

  @override
  void dispose() {
    _messageController.close();
    _taggedController.close();
    _connectionController.close();
    _fileListController.close();
    _sessionListController.close();
    super.dispose();
  }
}

Future<void> pumpN(WidgetTester tester, {int count = 5}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<Widget> buildTestHarness({
  required MockTestBridgeService bridge,
  required Widget child,
}) async {
  SharedPreferences.setMockInitialValues({});
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

Map<String, dynamic> _toMap(ClientMessage m) => jsonDecode(m.toJson()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Initial Prompt Dispatch and Rebuild Idempotency', () {
    late MockTestBridgeService bridge;

    setUp(() {
      bridge = MockTestBridgeService();
    });

    tearDown(() {
      bridge.dispose();
    });

    testWidgets('Codex: ready session dispatches initialPrompt exactly once', (tester) async {
      final widget = await buildTestHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'codex-ready-session',
          projectPath: '/workspace',
          initialPrompt: 'ANYCODING_PHASE1_CODEX_E2E_read_package_json',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      // Verify that the prompt was sent over bridge
      final inputMessages = bridge.sentMessages
          .where((m) => _toMap(m)['type'] == 'input')
          .where((m) => _toMap(m)['text'] == 'ANYCODING_PHASE1_CODEX_E2E_read_package_json')
          .toList();

      expect(inputMessages.length, 1);
      expect(_toMap(inputMessages.first)['sessionId'], 'codex-ready-session');

      // Rebuild / pump multiple frames and verify it does NOT send a second time
      await pumpN(tester);

      final countAfterPumps = bridge.sentMessages
          .where((m) => _toMap(m)['type'] == 'input')
          .where((m) => _toMap(m)['text'] == 'ANYCODING_PHASE1_CODEX_E2E_read_package_json')
          .length;
      expect(countAfterPumps, 1);

      // Drain delivery pending timer
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Codex: pending session dispatches initialPrompt only after session is resolved', (tester) async {
      final pendingNotifier = ValueNotifier<SystemMessage?>(null);

      final widget = await buildTestHarness(
        bridge: bridge,
        child: CodexSessionScreen(
          sessionId: 'pending-codex-temp-id',
          projectPath: '/workspace',
          isPending: true,
          pendingSessionCreated: pendingNotifier,
          initialPrompt: 'ANYCODING_PHASE1_CODEX_PENDING_PROMPT',
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump();

      // Pending state: should not have sent any prompt yet
      expect(
        bridge.sentMessages.where((m) => _toMap(m)['type'] == 'input').length,
        0,
      );

      // Now emit session_created
      pendingNotifier.value = const SystemMessage(
        subtype: 'session_created',
        sessionId: 'codex-resolved-real-id',
        projectPath: '/workspace',
      );

      await pumpN(tester);

      // After resolution, initial prompt should be sent to the resolved sessionId
      final inputMessages = bridge.sentMessages
          .where((m) => _toMap(m)['type'] == 'input')
          .where((m) => _toMap(m)['text'] == 'ANYCODING_PHASE1_CODEX_PENDING_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(_toMap(inputMessages.first)['sessionId'], 'codex-resolved-real-id');

      // Drain delivery pending timer
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Codex: disposing and rebuilding screen does NOT re-dispatch initial prompt', (tester) async {
      const sessionId = 'codex-rebuild-session-id';
      const prompt = 'CODEX_REBUILD_IDEMPOTENCY_PROMPT';

      // 1. First mount
      final widget1 = await buildTestHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: sessionId,
          projectPath: '/workspace',
          initialPrompt: prompt,
        ),
      );
      await tester.pumpWidget(widget1);
      await pumpN(tester);

      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == prompt)
            .length,
        1,
      );

      // 2. Unmount (dispose)
      await tester.pumpWidget(Container());
      await pumpN(tester);

      // 3. Mount second instance of CodexSessionScreen for same resolved session
      final widget2 = await buildTestHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: sessionId,
          projectPath: '/workspace',
          initialPrompt: prompt,
        ),
      );
      await tester.pumpWidget(widget2);
      await pumpN(tester);

      // Bridge outbound must still be exactly 1
      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == prompt)
            .length,
        1,
      );

      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Antigravity (Claude): ready session dispatches initialPrompt exactly once', (tester) async {
      final widget = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: 'antigravity-ready-session',
          provider: Provider.antigravity,
          projectPath: '/workspace',
          initialPrompt: 'ANYCODING_PHASE1_ANTIGRAVITY_PROMPT',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      final inputMessages = bridge.sentMessages
          .where((m) => _toMap(m)['type'] == 'input')
          .where((m) => _toMap(m)['text'] == 'ANYCODING_PHASE1_ANTIGRAVITY_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(_toMap(inputMessages.first)['sessionId'], 'antigravity-ready-session');

      // Drain delivery pending timer
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Antigravity (Claude): pending session dispatches initialPrompt only after session is resolved', (tester) async {
      final pendingNotifier = ValueNotifier<SystemMessage?>(null);

      final widget = await buildTestHarness(
        bridge: bridge,
        child: ClaudeSessionScreen(
          sessionId: 'pending-antigravity-temp-id',
          provider: Provider.antigravity,
          projectPath: '/workspace',
          isPending: true,
          pendingSessionCreated: pendingNotifier,
          initialPrompt: 'ANYCODING_PHASE1_ANTIGRAVITY_PENDING_PROMPT',
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump();

      expect(
        bridge.sentMessages.where((m) => _toMap(m)['type'] == 'input').length,
        0,
      );

      // Now emit session_created
      pendingNotifier.value = const SystemMessage(
        subtype: 'session_created',
        sessionId: 'antigravity-resolved-real-id',
        projectPath: '/workspace',
      );

      await pumpN(tester);

      final inputMessages = bridge.sentMessages
          .where((m) => _toMap(m)['type'] == 'input')
          .where((m) => _toMap(m)['text'] == 'ANYCODING_PHASE1_ANTIGRAVITY_PENDING_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(_toMap(inputMessages.first)['sessionId'], 'antigravity-resolved-real-id');

      // Drain delivery pending timer
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Antigravity (Claude): disposing and rebuilding screen does NOT re-dispatch initial prompt', (tester) async {
      const sessionId = 'antigravity-rebuild-session-id';
      const prompt = 'ANTIGRAVITY_REBUILD_IDEMPOTENCY_PROMPT';

      // 1. First mount
      final widget1 = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
          initialPrompt: prompt,
        ),
      );
      await tester.pumpWidget(widget1);
      await pumpN(tester);

      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == prompt)
            .length,
        1,
      );

      // 2. Unmount (dispose)
      await tester.pumpWidget(Container());
      await pumpN(tester);

      // 3. Mount second instance of ClaudeSessionScreen for same resolved session
      final widget2 = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
          initialPrompt: prompt,
        ),
      );
      await tester.pumpWidget(widget2);
      await pumpN(tester);

      // Bridge outbound must still be exactly 1
      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == prompt)
            .length,
        1,
      );

      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Antigravity: follow-up messages are NOT blocked by initial prompt tracking', (tester) async {
      const sessionId = 'antigravity-followup-test-session';
      const initialPrompt = 'ANYCODING_INITIAL_PROMPT';
      const followUpPrompt = 'FOLLOWUP_REPLY_OK_ONLY';

      final widget = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
          initialPrompt: initialPrompt,
        ),
      );
      await tester.pumpWidget(widget);
      await pumpN(tester);

      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == initialPrompt)
            .length,
        1,
      );

      // Emit idle status to simulate AI completion
      bridge.emitMessage(
        const StatusMessage(status: ProcessStatus.idle),
        sessionId: sessionId,
      );
      await pumpN(tester);

      final bodyElement = tester.element(find.byType(Scaffold).last);
      bodyElement.read<ChatSessionCubit>().sendMessage(followUpPrompt);
      await pumpN(tester);

      expect(
        bridge.sentMessages
            .where((m) => _toMap(m)['type'] == 'input')
            .where((m) => _toMap(m)['text'] == followUpPrompt)
            .length,
        1,
      );

      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('Session started chip is not duplicated when multiple init events arrive', (tester) async {
      final widget = await buildTestHarness(
        bridge: bridge,
        child: const CodexSessionScreen(
          sessionId: 'session-dedup-ui',
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      // Emit two init system messages with provider: 'codex'
      bridge.emitMessage(
        const SystemMessage(subtype: 'init', sessionId: 'session-dedup-ui', provider: 'codex'),
        sessionId: 'session-dedup-ui',
      );
      await pumpN(tester);

      bridge.emitMessage(
        const SystemMessage(subtype: 'init', sessionId: 'session-dedup-ui', provider: 'codex', projectPath: '/workspace'),
        sessionId: 'session-dedup-ui',
      );
      await pumpN(tester);

      // Only one "Session started" should be in the tree
      expect(find.text('Session started'), findsOneWidget);
    });

    testWidgets('Antigravity: identical assistant message entering via live + history/reconnect is deduplicated to exactly one in UI', (tester) async {
      const sessionId = 'antigravity-live-history-dedup';

      final widget = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      // 1. Live assistant message arrives
      const liveMsg = AssistantServerMessage(
        message: AssistantMessage(
          id: 'antigravity-response-msg-1',
          role: 'assistant',
          content: [
            TextContent(text: 'REPLY_EXACTLY_AE0549E_ONCE_RESULT'),
          ],
        ),
      );
      bridge.emitMessage(liveMsg, sessionId: sessionId);
      await pumpN(tester);

      expect(find.text('REPLY_EXACTLY_AE0549E_ONCE_RESULT'), findsOneWidget);

      // 2. Reconnect / History snapshot arrives containing the same message ID
      final historyMsg = HistoryMessage(
        messages: const [
          liveMsg,
        ],
      );
      bridge.emitMessage(historyMsg, sessionId: sessionId);
      await pumpN(tester);

      // Must STILL be exactly one in the UI
      expect(find.text('REPLY_EXACTLY_AE0549E_ONCE_RESULT'), findsOneWidget);
    });

    testWidgets('Antigravity: two different messages with identical text are legitimately preserved as two in UI', (tester) async {
      const sessionId = 'antigravity-distinct-id-preservation';

      final widget = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      // Message 1 in turn 1
      const msg1 = AssistantServerMessage(
        message: AssistantMessage(
          id: 'antigravity-turn-1-msg',
          role: 'assistant',
          content: [
            TextContent(text: 'OK'),
          ],
        ),
      );
      bridge.emitMessage(msg1, sessionId: sessionId);
      await pumpN(tester);

      // Message 2 in turn 2 with different ID but same text "OK"
      const msg2 = AssistantServerMessage(
        message: AssistantMessage(
          id: 'antigravity-turn-2-msg',
          role: 'assistant',
          content: [
            TextContent(text: 'OK'),
          ],
        ),
      );
      bridge.emitMessage(msg2, sessionId: sessionId);
      await pumpN(tester);

      // Both legitimate messages should be preserved in UI
      expect(find.text('OK'), findsNWidgets(2));
    });

    testWidgets('Antigravity: tool events with stable ID are deduplicated and do not duplicate across live/history', (tester) async {
      const sessionId = 'antigravity-tool-dedup';

      final widget = await buildTestHarness(
        bridge: bridge,
        child: const ClaudeSessionScreen(
          sessionId: sessionId,
          provider: Provider.antigravity,
          projectPath: '/workspace',
        ),
      );

      await tester.pumpWidget(widget);
      await pumpN(tester);

      const toolMsg = AssistantServerMessage(
        message: AssistantMessage(
          id: 'tool-use-list-dir-123',
          role: 'assistant',
          content: [
            ToolUseContent(
              id: 'tool-use-list-dir-123',
              name: 'list_dir',
              input: {'DirectoryPath': '/workspace'},
            ),
          ],
        ),
      );

      // 1. Live tool event arrives
      bridge.emitMessage(toolMsg, sessionId: sessionId);
      await pumpN(tester);

      expect(find.text('list_dir'), findsOneWidget);

      // 2. History snapshot arrives containing the same tool event
      final historyMsg = HistoryMessage(
        messages: const [
          toolMsg,
        ],
      );
      bridge.emitMessage(historyMsg, sessionId: sessionId);
      await pumpN(tester);

      // UI should still have only 1 list_dir widget
      expect(find.text('list_dir'), findsOneWidget);
    });
  });
}
