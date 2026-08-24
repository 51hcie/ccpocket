import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../services/platform_environment_service.dart';

/// The 4 standard AnyCoding task categories.
enum AnyCodingTaskCategory {
  /// Task is currently running, executing, starting, or active.
  inProgress('进行中', 'in_progress'),

  /// Task requires user attention: tool approval, question answer, or error to resolve.
  pending('待处理', 'pending'),

  /// Task has finished successfully or is archived history without errors.
  completed('已完成', 'completed'),

  /// Task encountered a fatal error or failed execution.
  failed('失败', 'failed');

  final String label;
  final String key;
  const AnyCodingTaskCategory(this.label, this.key);
}

/// Provider filter for AnyCoding (Codex vs Antigravity only, no Claude).
enum AnyCodingEngineFilter {
  all('全部', 'all'),
  codex('Codex', 'codex'),
  antigravity('Antigravity', 'antigravity');

  final String label;
  final String value;
  const AnyCodingEngineFilter(this.label, this.value);
}

/// Unified task item representation across active sessions, history, and offline queues.
class AnyCodingTaskItem {
  final String id;
  final Provider provider;
  final String projectPath;
  final String projectName;
  final String title;
  final AnyCodingTaskCategory category;
  final String rawStatus;
  final String statusLabel;
  final DateTime? updatedAt;
  final String? gitBranch;
  final String? worktreePath;
  final SessionInfo? activeSession;
  final RecentSession? recentSession;
  final OfflinePendingAction? offlineAction;
  final PermissionRequestMessage? pendingPermission;
  final bool isPinned;

  const AnyCodingTaskItem({
    required this.id,
    required this.provider,
    required this.projectPath,
    required this.projectName,
    required this.title,
    required this.category,
    required this.rawStatus,
    required this.statusLabel,
    this.updatedAt,
    this.gitBranch,
    this.worktreePath,
    this.activeSession,
    this.recentSession,
    this.offlineAction,
    this.pendingPermission,
    this.isPinned = false,
  });

  bool get isActive => activeSession != null || offlineAction != null;
  bool get hasPendingAction =>
      pendingPermission != null ||
      category == AnyCodingTaskCategory.pending;
}

/// Pure functions for classifying, filtering, and formatting AnyCoding tasks.
class TaskStatusClassifier {
  const TaskStatusClassifier._();

  /// Shortens an absolute path by replacing home directory with `~`.
  static String shortenHomePath(String path) {
    final home = getHomeDirectory();
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// Extracts the last path component as the friendly project directory name.
  static String extractProjectShortName(String projectPath) {
    if (projectPath.isEmpty) return '未命名项目';
    final normalized = projectPath.replaceAll(r'', '/');
    final trimmed = normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final parts = trimmed.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return projectPath;
    return parts.last;
  }

  /// Middle-truncates a long path: e.g. `~/.../candidates/ccpocket`.
  static String formatMiddleEllipsisPath(String projectPath, {int maxLength = 32}) {
    if (projectPath.isEmpty) return '';
    final short = shortenHomePath(projectPath);
    if (short.length <= maxLength) return short;

    final targetLength = maxLength - 3; // accounting for '...'
    if (targetLength <= 6) return short.substring(0, maxLength);

    final frontChars = (targetLength * 0.4).floor();
    final backChars = targetLength - frontChars;

    final prefix = short.substring(0, frontChars);
    final suffix = short.substring(short.length - backChars);
    return '$prefix...$suffix';
  }

  /// Formats a user-friendly task title without using raw absolute paths as title.
  static String formatTaskTitle({
    String? name,
    required String firstPrompt,
    String? summary,
    String? lastPrompt,
  }) {
    final customName = name?.trim();
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    final summaryText = summary?.trim();
    if (summaryText != null && summaryText.isNotEmpty) {
      return summaryText;
    }
    final prompt = firstPrompt.trim();
    if (prompt.isNotEmpty) {
      return prompt.replaceAll(r'
', ' ');
    }
    final last = lastPrompt?.trim();
    if (last != null && last.isNotEmpty) {
      return last.replaceAll(r'
', ' ');
    }
    return '新建任务';
  }

  /// Classifies a live [SessionInfo] into an [AnyCodingTaskCategory].
  ///
  /// CRITICAL: Unknown statuses FAIL-CLOSED to [AnyCodingTaskCategory.failed]
  /// or [AnyCodingTaskCategory.inProgress], NEVER [AnyCodingTaskCategory.completed]!
  ///
  /// Active sessions with `status == 'idle'` are waiting for user instructions,
  /// so they are classified as [AnyCodingTaskCategory.inProgress] (active), NOT completed.
  static AnyCodingTaskCategory classifySessionInfo(SessionInfo session) {
    if (session.pendingPermission != null) {
      return AnyCodingTaskCategory.pending;
    }

    final normalizedStatus = session.status.trim().toLowerCase();
    switch (normalizedStatus) {
      case 'waiting_approval':
      case 'waiting_for_input':
      case 'waiting_user':
      case 'ask_user':
        return AnyCodingTaskCategory.pending;

      case 'running':
      case 'starting':
      case 'compacting':
      case 'in_progress':
      case 'streaming':
      case 'idle': // Active session awaiting next user prompt
        return AnyCodingTaskCategory.inProgress;

      case 'completed':
      case 'done':
      case 'success':
        return AnyCodingTaskCategory.completed;

      case 'failed':
      case 'error':
      case 'stopped':
      case 'terminated':
        return AnyCodingTaskCategory.failed;

      default:
        // Fail-closed rule: Unrecognized status must NEVER report as completed!
        return AnyCodingTaskCategory.failed;
    }
  }

  /// Classifies a historical [RecentSession] into an [AnyCodingTaskCategory].
  static AnyCodingTaskCategory classifyRecentSession(RecentSession session) {
    if (session.isSidechain || session.sessionId.isEmpty) {
      return AnyCodingTaskCategory.failed;
    }
    return AnyCodingTaskCategory.completed;
  }

  /// Classifies an [OfflinePendingAction] into an [AnyCodingTaskCategory].
  static AnyCodingTaskCategory classifyOfflineAction(OfflinePendingAction action) {
    return AnyCodingTaskCategory.inProgress;
  }

  /// Resolves the provider enum from a string, ensuring only Codex & Antigravity are used in AnyCoding.
  static Provider resolveProvider(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'antigravity') {
      return Provider.antigravity;
    }
    return Provider.codex;
  }

  /// Maps an [AnyCodingTaskCategory] to a localized Chinese status label.
  static String statusLabelForCategory(AnyCodingTaskCategory category, String rawStatus) {
    switch (category) {
      case AnyCodingTaskCategory.inProgress:
        if (rawStatus == 'running' || rawStatus == 'streaming') return '运行中';
        if (rawStatus == 'starting') return '启动中';
        if (rawStatus == 'compacting') return '整理上下文';
        if (rawStatus == 'idle') return '等待指令';
        return '执行中';
      case AnyCodingTaskCategory.pending:
        if (rawStatus == 'waiting_approval') return '等待审批';
        if (rawStatus == 'waiting_for_input') return '等待回答';
        return '需处理';
      case AnyCodingTaskCategory.completed:
        return '已完成';
      case AnyCodingTaskCategory.failed:
        return '失败';
    }
  }

  /// Parses an ISO date string safely.
  static DateTime? parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Deduplicates and builds a consolidated list of [AnyCodingTaskItem]s from
  /// active sessions, recent sessions, and offline actions.
  static List<AnyCodingTaskItem> buildUnifiedTaskList({
    required List<SessionInfo> activeSessions,
    required List<RecentSession> recentSessions,
    List<OfflinePendingAction> offlinePendingActions = const [],
    Set<String> pinnedKeys = const {},
  }) {
    final items = <AnyCodingTaskItem>[];
    final seenActiveSessionIds = <String>{};

    // 1. Process active sessions (highest priority)
    for (final s in activeSessions) {
      // In AnyCoding brand mode, hide Claude sessions
      if (s.provider == 'claude') continue;

      final category = classifySessionInfo(s);
      final provider = resolveProvider(s.provider);
      final projectName = extractProjectShortName(s.projectPath);
      final title = formatTaskTitle(
        name: s.name,
        firstPrompt: s.lastMessage.isNotEmpty ? s.lastMessage : s.name ?? '',
        summary: s.name,
      );
      final rawStatus = s.status;
      final statusLabel = statusLabelForCategory(category, rawStatus);
      final updatedAt = parseDateTime(s.lastActivityAt) ?? parseDateTime(s.createdAt);

      seenActiveSessionIds.add(s.id);
      if (s.claudeSessionId != null && s.claudeSessionId!.isNotEmpty) {
        seenActiveSessionIds.add(s.claudeSessionId!);
      }

      items.add(
        AnyCodingTaskItem(
          id: s.id,
          provider: provider,
          projectPath: s.projectPath,
          projectName: projectName,
          title: title,
          category: category,
          rawStatus: rawStatus,
          statusLabel: statusLabel,
          updatedAt: updatedAt,
          gitBranch: s.gitBranch.isNotEmpty ? s.gitBranch : s.worktreeBranch,
          worktreePath: s.worktreePath,
          activeSession: s,
          pendingPermission: s.pendingPermission,
          isPinned: pinnedKeys.contains(s.id),
        ),
      );
    }

    // 2. Process offline pending actions
    for (final a in offlinePendingActions) {
      if (a.provider == 'claude') continue;
      if (a.sessionId != null && seenActiveSessionIds.contains(a.sessionId)) {
        continue;
      }
      final provider = resolveProvider(a.provider);
      final projectName = extractProjectShortName(a.projectPath);
      final title = a.sessionId != null ? '离线恢复任务' : '离线新建任务';
      final category = classifyOfflineAction(a);
      final statusLabel = '排队中';

      if (a.sessionId != null) {
        seenActiveSessionIds.add(a.sessionId!);
      }

      items.add(
        AnyCodingTaskItem(
          id: a.id,
          provider: provider,
          projectPath: a.projectPath,
          projectName: projectName,
          title: title,
          category: category,
          rawStatus: 'queued',
          statusLabel: statusLabel,
          updatedAt: a.createdAt,
          offlineAction: a,
          isPinned: false,
        ),
      );
    }

    // 3. Process historical recent sessions (excluding duplicates)
    for (final r in recentSessions) {
      if (r.provider == 'claude') continue;
      if (seenActiveSessionIds.contains(r.sessionId)) continue;

      final category = classifyRecentSession(r);
      final provider = resolveProvider(r.provider);
      final projectName = extractProjectShortName(r.projectPath);
      final title = formatTaskTitle(
        name: r.name,
        firstPrompt: r.firstPrompt,
        summary: r.summary,
        lastPrompt: r.lastPrompt,
      );
      final rawStatus = category == AnyCodingTaskCategory.completed ? 'completed' : 'failed';
      final statusLabel = statusLabelForCategory(category, rawStatus);
      final updatedAt = parseDateTime(r.modified) ?? parseDateTime(r.created);

      items.add(
        AnyCodingTaskItem(
          id: r.sessionId,
          provider: provider,
          projectPath: r.projectPath,
          projectName: projectName,
          title: title,
          category: category,
          rawStatus: rawStatus,
          statusLabel: statusLabel,
          updatedAt: updatedAt,
          gitBranch: r.gitBranch,
          worktreePath: r.resumeCwd,
          recentSession: r,
          isPinned: pinnedKeys.contains(r.sessionId),
        ),
      );
    }

    return items;
  }

  /// Filters tasks by category, engine/provider, and text search query.
  static List<AnyCodingTaskItem> filterTasks({
    required List<AnyCodingTaskItem> tasks,
    AnyCodingTaskCategory? category,
    AnyCodingEngineFilter engineFilter = AnyCodingEngineFilter.all,
    String query = '',
  }) {
    var result = tasks;

    if (category != null) {
      result = result.where((t) => t.category == category).toList();
    }

    if (engineFilter != AnyCodingEngineFilter.all) {
      final expectedProvider = engineFilter == AnyCodingEngineFilter.antigravity
          ? Provider.antigravity
          : Provider.codex;
      result = result.where((t) => t.provider == expectedProvider).toList();
    }

    final trimmedQuery = query.trim().toLowerCase();
    if (trimmedQuery.isNotEmpty) {
      result = result.where((t) {
        return t.title.toLowerCase().contains(trimmedQuery) ||
            t.projectName.toLowerCase().contains(trimmedQuery) ||
            t.projectPath.toLowerCase().contains(trimmedQuery) ||
            (t.gitBranch?.toLowerCase().contains(trimmedQuery) ?? false);
      }).toList();
    }

    return result;
  }

  /// Extracts unique projects from sessions and history.
  static List<({String path, String name, int activeCount, int totalCount})> buildProjectSummaries({
    required List<AnyCodingTaskItem> allTasks,
    required Iterable<String> projectPaths,
  }) {
    final seen = <String>{};
    final map = <String, ({String path, String name, int activeCount, int totalCount})>{};

    for (final task in allTasks) {
      final path = task.projectPath;
      if (path.isEmpty) continue;
      seen.add(path);
      final current = map[path];
      final activeInc = task.isActive ? 1 : 0;
      if (current == null) {
        map[path] = (
          path: path,
          name: task.projectName,
          activeCount: activeInc,
          totalCount: 1,
        );
      } else {
        map[path] = (
          path: path,
          name: current.name,
          activeCount: current.activeCount + activeInc,
          totalCount: current.totalCount + 1,
        );
      }
    }

    for (final rawPath in projectPaths) {
      final path = rawPath.trim();
      if (path.isEmpty || seen.contains(path)) continue;
      seen.add(path);
      map[path] = (
        path: path,
        name: extractProjectShortName(path),
        activeCount: 0,
        totalCount: 0,
      );
    }

    return map.values.toList();
  }
}
