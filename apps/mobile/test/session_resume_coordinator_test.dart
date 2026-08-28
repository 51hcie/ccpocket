import 'dart:convert';

import 'package:ccpocket/features/session_list/services/session_resume_coordinator.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/models/offline_pending_action.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResumeBridge extends BridgeService {
  final sentMessages = <ClientMessage>[];
  List<OfflinePendingAction> pendingActions = const [];

  @override
  List<OfflinePendingAction> get offlinePendingActions => pendingActions;

  @override
  void send(ClientMessage message) {
    sentMessages.add(message);
  }
}

const _session = RecentSession(
  sessionId: 'claude-uuid',
  provider: 'claude',
  rawPermissionMode: 'acceptEdits',
  firstPrompt: 'Continue',
  created: '2026-07-24T00:00:00Z',
  modified: '2026-07-24T01:00:00Z',
  gitBranch: 'main',
  projectPath: '/workspace/app',
  resumeCwd: '/workspace/app/worktree',
  isSidechain: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ResumeBridge bridge;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'claude_session_settings_claude-uuid': jsonEncode({
        'permissionMode': 'plan',
        'executionMode': 'plan',
        'planMode': true,
        'sandboxMode': 'on',
        'claudeEffort': 'high',
        'claudeModel': 'opus',
        'claudeFallbackModel': 'sonnet',
        'claudeForkSession': true,
        'claudePersistSession': false,
      }),
    });
    bridge = _ResumeBridge();
  });

  tearDown(() {
    bridge.dispose();
  });

  test('resumes a deep link with the same persisted Claude settings', () async {
    final result = await SessionResumeCoordinator(bridge: bridge)
        .resume(_session, resumeRequestId: 'link-request-1');

    expect(result.disposition, SessionResumeDisposition.dispatched);
    expect(result.projectPath, '/workspace/app/worktree');
    final message =
        jsonDecode(bridge.sentMessages.single.toJson()) as Map<String, dynamic>;
    expect(message, containsPair('type', 'resume_session'));
    expect(message, containsPair('sessionId', 'claude-uuid'));
    expect(message, containsPair('projectPath', '/workspace/app/worktree'));
    expect(message, containsPair('permissionMode', 'plan'));
    expect(message, containsPair('executionMode', 'default'));
    expect(message, containsPair('planMode', true));
    expect(message, containsPair('sandboxMode', 'on'));
    expect(message, containsPair('effort', 'high'));
    expect(message, containsPair('model', 'opus'));
    expect(message, containsPair('fallbackModel', 'sonnet'));
    expect(message, containsPair('forkSession', true));
    expect(message, containsPair('persistSession', false));
    expect(message, containsPair('resumeRequestId', 'link-request-1'));
  });

  test('does not enqueue the same offline resume twice', () async {
    bridge.pendingActions = [
      OfflinePendingAction(
        id: 'resume:claude-uuid',
        kind: OfflinePendingActionKind.resume,
        projectPath: _session.projectPath,
        provider: 'claude',
        createdAt: DateTime.utc(2026, 7, 24),
        sessionId: _session.sessionId,
      ),
    ];

    final result = await SessionResumeCoordinator(bridge: bridge)
        .resume(_session);

    expect(result.disposition, SessionResumeDisposition.alreadyQueued);
    expect(bridge.sentMessages, isEmpty);
  });

  test('infers codex provider from codexSettings when provider is missing and resumes with provider=codex', () async {
    final session = RecentSession.fromJson({
      'sessionId': '01a00976-b3f1-7831-8e03-b61c86acfac7',
      // provider is omitted/missing
      'firstPrompt': 'Codex task without provider',
      'created': '2026-08-25T00:00:00Z',
      'modified': '2026-08-25T01:00:00Z',
      'gitBranch': 'main',
      'projectPath': '/workspace/app',
      'codexSettings': {
        'approvalPolicy': 'never',
        'model': 'gpt-5.4',
      },
    });

    expect(session.isCodex, isTrue);
    expect(session.provider, 'codex');

    final result = await SessionResumeCoordinator(bridge: bridge).resume(session);

    expect(result.disposition, SessionResumeDisposition.dispatched);
    expect(bridge.sentMessages, hasLength(1));
    final message = jsonDecode(bridge.sentMessages.single.toJson()) as Map<String, dynamic>;
    expect(message['type'], 'resume_session');
    expect(message['sessionId'], '01a00976-b3f1-7831-8e03-b61c86acfac7');
    expect(message['provider'], 'codex');
  });

  test('fails closed and does not dispatch when provider is missing and cannot be inferred', () async {
    final session = RecentSession.fromJson({
      'sessionId': 'unknown-session-without-provider',
      // provider is omitted/missing
      'firstPrompt': 'Mystery session',
      'created': '2026-08-25T00:00:00Z',
      'modified': '2026-08-25T01:00:00Z',
      'gitBranch': 'main',
      'projectPath': '/workspace/app',
    });

    expect(session.provider, isNull);
    expect(session.isCodex, isFalse);

    final result = await SessionResumeCoordinator(bridge: bridge).resume(session);

    expect(result.disposition, SessionResumeDisposition.unresolvedProvider);
    expect(result.errorMessage, contains('无法识别会话引擎提供方'));
    // CRITICAL: Fail-closed safeguard: must NOT send resume_session or default to Claude!
    expect(bridge.sentMessages, isEmpty);
  });

  test('infers antigravity provider when antigravityConversationId is present and resumes with provider=antigravity', () async {
    final session = RecentSession.fromJson({
      'sessionId': 'agy-session-123',
      // provider is omitted/missing
      'antigravityConversationId': 'agy-conv-999',
      'firstPrompt': 'Antigravity session',
      'created': '2026-08-25T00:00:00Z',
      'modified': '2026-08-25T01:00:00Z',
      'gitBranch': 'main',
      'projectPath': '/workspace/app',
    });

    expect(session.provider, 'antigravity');

    final result = await SessionResumeCoordinator(bridge: bridge).resume(session);

    expect(result.disposition, SessionResumeDisposition.dispatched);
    expect(bridge.sentMessages, hasLength(1));
    final message = jsonDecode(bridge.sentMessages.single.toJson()) as Map<String, dynamic>;
    expect(message['type'], 'resume_session');
    expect(message['sessionId'], 'agy-session-123');
    expect(message['provider'], 'antigravity');
  });
}
