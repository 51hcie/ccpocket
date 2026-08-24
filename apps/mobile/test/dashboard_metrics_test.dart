import 'package:flutter_test/flutter_test.dart';
import 'package:ccpocket/features/session_list/services/dashboard_metrics_calculator.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/models/offline_pending_action.dart';

void main() {
  group('Dashboard Engine Status Resolution (Task 1)', () {
    test('Codex status is Offline when Bridge is not connected', () {
      final status = resolveCodexStatus(
        isConnected: false,
        codexModels: ['gpt-5.2-codex'],
      );
      expect(status, EngineAvailabilityStatus.offline);
      expect(status.label, 'Offline');
      expect(status.isOnline, isFalse);
    });

    test('Codex status is Ready when connected and models are available', () {
      final status = resolveCodexStatus(
        isConnected: true,
        codexModels: ['gpt-5.2-codex', 'gpt-5-codex'],
      );
      expect(status, EngineAvailabilityStatus.ready);
      expect(status.label, 'Ready');
      expect(status.isOnline, isTrue);
    });

    test('Codex status is Supported when connected but no models reported', () {
      final status = resolveCodexStatus(
        isConnected: true,
        codexModels: const [],
      );
      expect(status, EngineAvailabilityStatus.supported);
      expect(status.label, 'Supported');
      expect(status.isOnline, isTrue);
    });

    test(
      'Antigravity status is Offline when Bridge is not connected',
      () {
        final status = resolveAntigravityStatus(isConnected: false);
        expect(status, EngineAvailabilityStatus.offline);
        expect(status.label, 'Offline');
        expect(status.isOnline, isFalse);
      },
    );

    test(
      'Antigravity status is Supported (not falsely Ready) when connected without probe',
      () {
        final status = resolveAntigravityStatus(
          isConnected: true,
          hasProbingSupport: false,
        );
        expect(status, EngineAvailabilityStatus.supported);
        expect(status.label, 'Supported');
        expect(status.isOnline, isTrue);
      },
    );

    test(
      'Antigravity status is Ready when probe capability is active and probe succeeds',
      () {
        final status = resolveAntigravityStatus(
          isConnected: true,
          hasProbingSupport: true,
          isProbedReady: true,
        );
        expect(status, EngineAvailabilityStatus.ready);
        expect(status.label, 'Ready');
        expect(status.isOnline, isTrue);
      },
    );

    test(
      'Antigravity status is Unavailable when probe capability is active but probe fails',
      () {
        final status = resolveAntigravityStatus(
          isConnected: true,
          hasProbingSupport: true,
          isProbedReady: false,
        );
        expect(status, EngineAvailabilityStatus.unavailable);
        expect(status.label, 'Unavailable');
        expect(status.isOnline, isTrue);
      },
    );
  });

  group('Dashboard Task Statistics Calculation (Task 2)', () {
    const activeRunning1 = SessionInfo(
      id: 'session-run-1',
      provider: 'antigravity',
      projectPath: '/path/to/project-a',
      status: 'running',
      createdAt: '2026-08-23T10:00:00Z',
      lastActivityAt: '2026-08-23T10:00:00Z',
    );

    const activeRunning2 = SessionInfo(
      id: 'session-run-2',
      provider: 'codex',
      projectPath: '/path/to/project-b',
      status: 'running',
      createdAt: '2026-08-23T10:05:00Z',
      lastActivityAt: '2026-08-23T10:05:00Z',
    );

    const activeIdleSession = SessionInfo(
      id: 'session-idle-1',
      provider: 'codex',
      projectPath: '/path/to/project-c',
      status: 'idle', // ACTIVE, NOT COMPLETED!
      createdAt: '2026-08-23T10:10:00Z',
      lastActivityAt: '2026-08-23T10:10:00Z',
    );

    const activeWaitingForInput = SessionInfo(
      id: 'session-wait-1',
      provider: 'antigravity',
      projectPath: '/path/to/project-d',
      status: 'waiting_for_input',
      createdAt: '2026-08-23T10:15:00Z',
      lastActivityAt: '2026-08-23T10:15:00Z',
    );

    const activePendingPermission = SessionInfo(
      id: 'session-wait-2',
      provider: 'codex',
      projectPath: '/path/to/project-e',
      status: 'running',
      pendingPermission: PermissionRequestMessage(
        toolUseId: 'perm-1',
        toolName: 'ExecuteCommand',
        input: {'command': 'ls'},
      ),
      createdAt: '2026-08-23T10:20:00Z',
      lastActivityAt: '2026-08-23T10:20:00Z',
    );

    const activeFailed = SessionInfo(
      id: 'session-fail-1',
      provider: 'claude',
      projectPath: '/path/to/project-f',
      status: 'failed',
      createdAt: '2026-08-23T10:25:00Z',
      lastActivityAt: '2026-08-23T10:25:00Z',
    );

    const activeError = SessionInfo(
      id: 'session-err-1',
      provider: 'codex',
      projectPath: '/path/to/project-g',
      status: 'error',
      createdAt: '2026-08-23T10:30:00Z',
      lastActivityAt: '2026-08-23T10:30:00Z',
    );

    const activeCompleted = SessionInfo(
      id: 'session-completed-1',
      provider: 'antigravity',
      projectPath: '/path/to/project-h',
      status: 'completed',
      createdAt: '2026-08-23T10:35:00Z',
      lastActivityAt: '2026-08-23T10:35:00Z',
    );

    const recentCompleted1 = RecentSession(
      sessionId: 'recent-done-1',
      provider: 'codex',
      firstPrompt: 'Build feature',
      created: '2026-08-23T08:00:00Z',
      modified: '2026-08-23T08:30:00Z',
      gitBranch: 'main',
      projectPath: '/path/to/project-done-1',
      isSidechain: false,
    );

    const recentCompleted2 = RecentSession(
      sessionId: 'recent-done-2',
      provider: 'antigravity',
      firstPrompt: 'Analyze architecture',
      created: '2026-08-23T09:00:00Z',
      modified: '2026-08-23T09:30:00Z',
      gitBranch: 'main',
      projectPath: '/path/to/project-done-2',
      isSidechain: false,
    );

    // Duplicate of activeRunning1 by sessionId
    const recentDuplicateActive = RecentSession(
      sessionId: 'session-run-1',
      provider: 'antigravity',
      firstPrompt: 'Plan task',
      created: '2026-08-23T10:00:00Z',
      modified: '2026-08-23T10:05:00Z',
      gitBranch: 'main',
      projectPath: '/path/to/project-a',
      isSidechain: false,
    );

    // Duplicate of activeIdleSession by provider+path+createdAt
    const recentDuplicateIdle = RecentSession(
      sessionId: 'recent-proxy-idle',
      provider: 'codex',
      firstPrompt: 'Check status',
      created: '2026-08-23T10:10:00Z',
      modified: '2026-08-23T10:12:00Z',
      gitBranch: 'main',
      projectPath: '/path/to/project-c',
      isSidechain: false,
    );

    test(
        'counts running, waiting, failed, and done accurately without duplicates',
        () {
      final counts = calculateDashboardTaskCounts(
        activeSessions: [
          activeRunning1,
          activeRunning2,
          activeIdleSession,
          activeWaitingForInput,
          activePendingPermission,
          activeFailed,
          activeError,
          activeCompleted,
        ],
        recentSessions: [
          recentCompleted1,
          recentCompleted2,
          recentDuplicateActive, // duplicate of activeRunning1
          recentDuplicateIdle, // duplicate of activeIdleSession
        ],
      );

      // Running: activeRunning1 + activeRunning2 (activePendingPermission is waiting, activeIdle is idle)
      expect(counts.running, 2);

      // Waiting: activeWaitingForInput + activePendingPermission
      expect(counts.waiting, 2);

      // Failed: activeFailed + activeError
      expect(counts.failed, 2);

      // Completed (Done):
      // - recentCompleted1 (non-duplicate)
      // - recentCompleted2 (non-duplicate)
      // - activeCompleted
      // MUST NOT INCLUDE activeIdleSession or duplicates!
      expect(counts.completed, 3);
    });

    test('does NOT count active idle session as completed or running', () {
      final counts = calculateDashboardTaskCounts(
        activeSessions: [activeIdleSession],
        recentSessions: const [],
      );

      expect(counts.running, 0);
      expect(counts.waiting, 0);
      expect(counts.failed, 0);
      expect(counts.completed, 0);
    });

    test('includes offline pending actions in running count', () {
      final offlineActions = [
        OfflinePendingAction(
          id: 'action-1',
          kind: OfflinePendingActionKind.start,
          projectPath: '/path/to/project-a',
          provider: 'antigravity',
          createdAt: DateTime.parse('2026-08-23T10:00:00Z'),
          sessionId: 'session-run-1',
        ),
      ];

      final counts = calculateDashboardTaskCounts(
        activeSessions: [activeRunning1],
        recentSessions: const [],
        offlinePendingActions: offlineActions,
      );

      expect(counts.running, 2); // 1 active running + 1 offline pending action
    });

    test('deduplicates recent sessions matching pending resume actions', () {
      final offlineResume = [
        OfflinePendingAction(
          id: 'action-resume-1',
          kind: OfflinePendingActionKind.resume,
          projectPath: '/path/to/project-done-1',
          provider: 'codex',
          createdAt: DateTime.parse('2026-08-23T08:00:00Z'),
          sessionId: 'recent-done-1',
        ),
      ];

      final counts = calculateDashboardTaskCounts(
        activeSessions: const [],
        recentSessions: [recentCompleted1, recentCompleted2],
        offlinePendingActions: offlineResume,
      );

      // recentCompleted1 is pending resume, so deduplicated
      expect(counts.completed, 1);
      expect(counts.running, 1); // pending resume counted in offline actions
    });
  });

  group('Provider Message Placeholder Resolution', () {
    test('resolves Antigravity message placeholder', () {
      final placeholder = resolveMessagePlaceholder(
        provider: Provider.antigravity,
      );
      expect(placeholder, 'Message Antigravity...');
    });

    test('resolves Codex message placeholder with default fallback', () {
      final placeholder = resolveMessagePlaceholder(
        provider: Provider.codex,
      );
      expect(placeholder, 'Message Codex...');
    });

    test('resolves Codex message placeholder with custom localization', () {
      final placeholder = resolveMessagePlaceholder(
        provider: Provider.codex,
        codexPlaceholder: 'Codex にメッセージ...',
      );
      expect(placeholder, 'Codex にメッセージ...');
    });

    test('resolves Claude message placeholder by default for null or claude', () {
      expect(
        resolveMessagePlaceholder(provider: Provider.claude),
        'Message Claude...',
      );
      expect(
        resolveMessagePlaceholder(provider: null),
        'Message Claude...',
      );
      expect(
        resolveMessagePlaceholder(
          provider: Provider.claude,
          claudePlaceholder: 'Claude にメッセージ...',
        ),
        'Claude にメッセージ...',
      );
    });

    test('resolves AnyCoding message placeholder when isAnyCoding is true', () {
      expect(
        resolveMessagePlaceholder(
          provider: Provider.codex,
          isAnyCoding: true,
        ),
        '继续下达指令...',
      );
      expect(
        resolveMessagePlaceholder(
          provider: Provider.antigravity,
          isAnyCoding: true,
          anycodingPlaceholder: '自定义下达指令...',
        ),
        '自定义下达指令...',
      );
    });
  });
}
