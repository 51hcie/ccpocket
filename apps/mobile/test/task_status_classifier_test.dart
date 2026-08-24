import 'package:flutter_test/flutter_test.dart';
import 'package:ccpocket/features/anycoding/services/task_status_classifier.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/models/offline_pending_action.dart';

void main() {
  group('TaskStatusClassifier - Status Categorization & Fail-Closed Rules', () {
    test('classifies running and starting sessions as inProgress', () {
      const runningSession = SessionInfo(
        id: 'run-1',
        provider: 'codex',
        projectPath: '/Users/test/workspace/app',
        status: 'running',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(runningSession),
        equals(AnyCodingTaskCategory.inProgress),
      );

      const startingSession = SessionInfo(
        id: 'start-1',
        provider: 'antigravity',
        projectPath: '/Users/test/workspace/app',
        status: 'starting',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(startingSession),
        equals(AnyCodingTaskCategory.inProgress),
      );
    });

    test('classifies active idle session as inProgress (never falsely completed)', () {
      const idleSession = SessionInfo(
        id: 'idle-1',
        provider: 'codex',
        projectPath: '/Users/test/workspace/app',
        status: 'idle',
        createdAt: '2026-08-24T00:00:00Z',
      );
      // Active idle session is awaiting user next command -> inProgress
      expect(
        TaskStatusClassifier.classifySessionInfo(idleSession),
        equals(AnyCodingTaskCategory.inProgress),
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(idleSession),
        isNot(equals(AnyCodingTaskCategory.completed)),
      );
    });

    test('classifies pending permission and waiting approval as pending', () {
      const permissionSession = SessionInfo(
        id: 'perm-1',
        provider: 'codex',
        projectPath: '/Users/test/workspace/app',
        status: 'running',
        createdAt: '2026-08-24T00:00:00Z',
        pendingPermission: PermissionRequestMessage(
          toolUseId: 't1',
          toolName: 'Bash',
          input: {'command': 'rm -rf tmp'},
        ),
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(permissionSession),
        equals(AnyCodingTaskCategory.pending),
      );

      const waitingSession = SessionInfo(
        id: 'wait-1',
        provider: 'antigravity',
        projectPath: '/Users/test/workspace/app',
        status: 'waiting_for_input',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(waitingSession),
        equals(AnyCodingTaskCategory.pending),
      );
    });

    test('classifies failed and error sessions as failed', () {
      const failedSession = SessionInfo(
        id: 'fail-1',
        provider: 'codex',
        projectPath: '/Users/test/workspace/app',
        status: 'failed',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(failedSession),
        equals(AnyCodingTaskCategory.failed),
      );

      const errorSession = SessionInfo(
        id: 'err-1',
        provider: 'antigravity',
        projectPath: '/Users/test/workspace/app',
        status: 'error',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(errorSession),
        equals(AnyCodingTaskCategory.failed),
      );
    });

    test('FAIL-CLOSED: unknown or unrecognized status is NEVER reported as completed', () {
      const unknownSession1 = SessionInfo(
        id: 'unk-1',
        provider: 'codex',
        projectPath: '/Users/test/workspace/app',
        status: 'some_weird_unrecognized_status',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(unknownSession1),
        isNot(equals(AnyCodingTaskCategory.completed)),
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(unknownSession1),
        equals(AnyCodingTaskCategory.failed),
      );

      const unknownSession2 = SessionInfo(
        id: 'unk-2',
        provider: 'antigravity',
        projectPath: '/Users/test/workspace/app',
        status: 'unspecified_state',
        createdAt: '2026-08-24T00:00:00Z',
      );
      expect(
        TaskStatusClassifier.classifySessionInfo(unknownSession2),
        isNot(equals(AnyCodingTaskCategory.completed)),
      );
    });

    test('classifies normal recent session as completed and corrupted as failed', () {
      const normalRecent = RecentSession(
        sessionId: 'rec-1',
        provider: 'codex',
        firstPrompt: 'Implement feature',
        created: '2026-08-24T00:00:00Z',
        modified: '2026-08-24T00:10:00Z',
        gitBranch: 'main',
        projectPath: '/path/project',
        isSidechain: false,
      );
      expect(
        TaskStatusClassifier.classifyRecentSession(normalRecent),
        equals(AnyCodingTaskCategory.completed),
      );

      const sidechainRecent = RecentSession(
        sessionId: 'rec-2',
        provider: 'codex',
        firstPrompt: 'Broken branch',
        created: '2026-08-24T00:00:00Z',
        modified: '2026-08-24T00:10:00Z',
        gitBranch: 'main',
        projectPath: '/path/project',
        isSidechain: true,
      );
      expect(
        TaskStatusClassifier.classifyRecentSession(sidechainRecent),
        equals(AnyCodingTaskCategory.failed),
      );
    });
  });

  group('TaskStatusClassifier - Path & String Utilities', () {
    test('extractProjectShortName extracts last folder name', () {
      expect(
        TaskStatusClassifier.extractProjectShortName('/Users/lw/Windows_Projects/ccpocket'),
        equals('ccpocket'),
      );
      expect(
        TaskStatusClassifier.extractProjectShortName('/workspace/sub/my-cool-agent/'),
        equals('my-cool-agent'),
      );
      expect(
        TaskStatusClassifier.extractProjectShortName(''),
        equals('未命名项目'),
      );
    });

    test('formatMiddleEllipsisPath truncates middle on long paths', () {
      const shortPath = '/code/app';
      expect(
        TaskStatusClassifier.formatMiddleEllipsisPath(shortPath, maxLength: 32),
        equals(shortPath),
      );

      const longPath = '/Users/someone/development/very/deeply/nested/directory/structure/my-project';
      final truncated = TaskStatusClassifier.formatMiddleEllipsisPath(longPath, maxLength: 30);
      expect(truncated.contains('...'), isTrue);
      expect(truncated.length, lessThanOrEqualTo(32));
      expect(truncated.endsWith('my-project'), isTrue);
    });

    test('formatTaskTitle prefers custom name > summary > prompt', () {
      expect(
        TaskStatusClassifier.formatTaskTitle(
          name: 'Custom Task Name',
          firstPrompt: 'Prompt text',
          summary: 'Summary text',
        ),
        equals('Custom Task Name'),
      );

      expect(
        TaskStatusClassifier.formatTaskTitle(
          name: null,
          firstPrompt: 'First prompt instruction',
          summary: 'Summary text',
        ),
        equals('Summary text'),
      );

      expect(
        TaskStatusClassifier.formatTaskTitle(
          name: null,
          firstPrompt: 'First prompt instruction',
          summary: null,
        ),
        equals('First prompt instruction'),
      );
    });
  });

  group('TaskStatusClassifier - Filtering & Project Summaries', () {
    final tasks = [
      const AnyCodingTaskItem(
        id: '1',
        provider: Provider.codex,
        projectPath: '/projects/repo-a',
        projectName: 'repo-a',
        title: 'Fix issue 1',
        category: AnyCodingTaskCategory.inProgress,
        rawStatus: 'running',
        statusLabel: '运行中',
      ),
      const AnyCodingTaskItem(
        id: '2',
        provider: Provider.antigravity,
        projectPath: '/projects/repo-b',
        projectName: 'repo-b',
        title: 'Refactor module',
        category: AnyCodingTaskCategory.completed,
        rawStatus: 'completed',
        statusLabel: '已完成',
      ),
      const AnyCodingTaskItem(
        id: '3',
        provider: Provider.codex,
        projectPath: '/projects/repo-a',
        projectName: 'repo-a',
        title: 'Approve script execution',
        category: AnyCodingTaskCategory.pending,
        rawStatus: 'waiting_approval',
        statusLabel: '等待审批',
      ),
    ];

    test('filters tasks by category', () {
      final inProgress = TaskStatusClassifier.filterTasks(
        tasks: tasks,
        category: AnyCodingTaskCategory.inProgress,
      );
      expect(inProgress.length, equals(1));
      expect(inProgress.first.id, equals('1'));

      final pending = TaskStatusClassifier.filterTasks(
        tasks: tasks,
        category: AnyCodingTaskCategory.pending,
      );
      expect(pending.length, equals(1));
      expect(pending.first.id, equals('3'));
    });

    test('filters tasks by engine provider', () {
      final codexTasks = TaskStatusClassifier.filterTasks(
        tasks: tasks,
        engineFilter: AnyCodingEngineFilter.codex,
      );
      expect(codexTasks.length, equals(2));

      final agyTasks = TaskStatusClassifier.filterTasks(
        tasks: tasks,
        engineFilter: AnyCodingEngineFilter.antigravity,
      );
      expect(agyTasks.length, equals(1));
      expect(agyTasks.first.id, equals('2'));
    });

    test('filters tasks by search query', () {
      final searchResult = TaskStatusClassifier.filterTasks(
        tasks: tasks,
        query: 'Refactor',
      );
      expect(searchResult.length, equals(1));
      expect(searchResult.first.projectName, equals('repo-b'));
    });

    test('builds unique project summaries with accurate counts', () {
      final summaries = TaskStatusClassifier.buildProjectSummaries(
        allTasks: tasks,
        projectPaths: ['/projects/repo-c'],
      );

      expect(summaries.length, equals(3));

      final repoA = summaries.firstWhere((p) => p.path == '/projects/repo-a');
      expect(repoA.name, equals('repo-a'));
      expect(repoA.totalCount, equals(2));

      final repoC = summaries.firstWhere((p) => p.path == '/projects/repo-c');
      expect(repoC.name, equals('repo-c'));
      expect(repoC.totalCount, equals(0));
    });
  });
}
