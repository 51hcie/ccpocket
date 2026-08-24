import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:ccpocket/features/claude_session/claude_session_screen.dart';
import 'package:ccpocket/features/codex_session/codex_session_screen.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Initial Prompt Dispatch in Real Provider Tree', () {
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
      await tester.pumpAndSettle();

      // Verify that the prompt was sent over bridge
      final inputMessages = bridge.sentMessages
          .where((m) => m.toJson()['type'] == 'input')
          .where((m) => m.toJson()['text'] == 'ANYCODING_PHASE1_CODEX_E2E_read_package_json')
          .toList();

      expect(inputMessages.length, 1);
      expect(inputMessages.first.toJson()['sessionId'], 'codex-ready-session');

      // Rebuild / pump multiple frames and verify it does NOT send a second time
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final countAfterPumps = bridge.sentMessages
          .where((m) => m.toJson()['type'] == 'input')
          .where((m) => m.toJson()['text'] == 'ANYCODING_PHASE1_CODEX_E2E_read_package_json')
          .length;
      expect(countAfterPumps, 1);
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
        bridge.sentMessages.where((m) => m.toJson()['type'] == 'input').length,
        0,
      );

      // Now emit session_created
      pendingNotifier.value = const SystemMessage(
        subtype: 'session_created',
        sessionId: 'codex-resolved-real-id',
        projectPath: '/workspace',
      );

      await tester.pumpAndSettle();

      // After resolution, initial prompt should be sent to the resolved sessionId
      final inputMessages = bridge.sentMessages
          .where((m) => m.toJson()['type'] == 'input')
          .where((m) => m.toJson()['text'] == 'ANYCODING_PHASE1_CODEX_PENDING_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(inputMessages.first.toJson()['sessionId'], 'codex-resolved-real-id');
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
      await tester.pumpAndSettle();

      final inputMessages = bridge.sentMessages
          .where((m) => m.toJson()['type'] == 'input')
          .where((m) => m.toJson()['text'] == 'ANYCODING_PHASE1_ANTIGRAVITY_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(inputMessages.first.toJson()['sessionId'], 'antigravity-ready-session');
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
        bridge.sentMessages.where((m) => m.toJson()['type'] == 'input').length,
        0,
      );

      // Now emit session_created
      pendingNotifier.value = const SystemMessage(
        subtype: 'session_created',
        sessionId: 'antigravity-resolved-real-id',
        projectPath: '/workspace',
      );

      await tester.pumpAndSettle();

      final inputMessages = bridge.sentMessages
          .where((m) => m.toJson()['type'] == 'input')
          .where((m) => m.toJson()['text'] == 'ANYCODING_PHASE1_ANTIGRAVITY_PENDING_PROMPT')
          .toList();

      expect(inputMessages.length, 1);
      expect(inputMessages.first.toJson()['sessionId'], 'antigravity-resolved-real-id');
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
      await tester.pumpAndSettle();

      // Emit two init system messages
      bridge.emitMessage(
        const SystemMessage(subtype: 'init', sessionId: 'session-dedup-ui'),
        sessionId: 'session-dedup-ui',
      );
      await tester.pumpAndSettle();

      bridge.emitMessage(
        const SystemMessage(subtype: 'init', sessionId: 'session-dedup-ui', projectPath: '/workspace'),
        sessionId: 'session-dedup-ui',
      );
      await tester.pumpAndSettle();

      // Only one "Session started" should be in the tree
      expect(find.text('Session started'), findsOneWidget);
    });
  });
}
