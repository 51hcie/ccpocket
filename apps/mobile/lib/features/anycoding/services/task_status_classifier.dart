import 'dart:io' show Platform;

import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';

/// The 5 standard AnyCoding task categories.
enum AnyCodingTaskCategory {
  /// 运行中: Task is currently running, executing, starting, streaming, or active idle.
  inProgress('运行中', 'in_progress'),

  /// 等待批准/回答: Task requires user attention (tool approval, user answer).
  waitingApproval('等待批准/回答', 'waiting_approval'),

  /// 接管排队: Task is queued in Bridge takeover queue or waiting for writer release.
  takeoverQueued('接管排队', 'takeover_queued'),

  /// 失败: Task encountered an error, was stopped/terminated, or failed execution.
  failed('失败', 'failed'),

  /// 已完成: Task finished successfully or is archived clean history.
  completed('已完成', 'completed');

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
      category == AnyCodingTaskCategory.waitingApproval;
}

/// Pure functions for classifying, filtering, and formatting AnyCoding tasks.
class TaskStatusClassifier {
  const TaskStatusClassifier._();

  /// Shortens an absolute path by replacing home directory with `~`.
  static String shortenHomePath(String path) {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty && path.startsWith(home)) {
        return '~${path.substring(home.length)}';
      }
    } catch (_) {}
    return path;
  }

  /// Normalizes a project path (trims, standardizes separators, strips trailing slashes).
  static String normalizeProjectPath(String? path) {
    if (path == null) return '';
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Extracts the last path component as the friendly project directory name.
  static String extractProjectShortName(String projectPath) {
    final normalized = normalizeProjectPath(projectPath);
    if (normalized.isEmpty) return '未命名项目';
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
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
      return prompt.split(RegExp(r'[\r\n]+')).join(' ');
    }
    final last = lastPrompt?.trim();
    if (last != null && last.isNotEmpty) {
      return last.split(RegExp(r'[\r\n]+')).join(' ');
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
  static AnyCodingTaskCategory classifySessionInfo(
    SessionInfo session, {
    CodexTakeoverQueueStatusMessage? takeoverQueueStatus,
  }) {
    if (takeoverQueueStatus != null && takeoverQueueStatus.status == 'queued') {
      return AnyCodingTaskCategory.takeoverQueued;
    }

    if (session.pendingPermission != null) {
      return AnyCodingTaskCategory.waitingApproval;
    }

    final normalizedStatus = session.status.trim().toLowerCase();
    switch (normalizedStatus) {
      case 'waiting_approval':
      case 'waiting_for_input':
      case 'waiting_user':
      case 'ask_user':
        return AnyCodingTaskCategory.waitingApproval;

      case 'takeover_queued':
      case 'queued':
        return AnyCodingTaskCategory.takeoverQueued;

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
    return AnyCodingTaskCategory.takeoverQueued;
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
  static String statusLabelForCategory(
    AnyCodingTaskCategory category,
    String rawStatus, {
    CodexTakeoverQueueStatusMessage? takeoverQueueStatus,
  }) {
    switch (category) {
      case AnyCodingTaskCategory.inProgress:
        if (rawStatus == 'running' || rawStatus == 'streaming') return '运行中';
        if (rawStatus == 'starting') return '启动中';
        if (rawStatus == 'compacting') return '整理上下文';
        if (rawStatus == 'idle') return '运行中 · 空闲';
        return '运行中';
      case AnyCodingTaskCategory.waitingApproval:
        if (rawStatus == 'waiting_approval') return '等待审批';
        if (rawStatus == 'waiting_for_input') return '等待回答';
        return '等待批准/回答';
      case AnyCodingTaskCategory.takeoverQueued:
        if (takeoverQueueStatus != null &&
            takeoverQueueStatus.status == 'queued' &&
            takeoverQueueStatus.position > 0) {
          return '排队中 (${takeoverQueueStatus.position}/${takeoverQueueStatus.total})';
        }
        return '接管排队中';
      case AnyCodingTaskCategory.completed:
        return '已完成';
      case AnyCodingTaskCategory.failed:
        if (rawStatus == 'stopped') return '已停止';
        return '失败';
    }
  }

  /// Parses an ISO date string safely.
  static DateTime? parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Deduplicates and builds a consolidated list of [AnyCodingTaskItem]s from
  /// active sessions, recent sessions, and offline actions, strictly sorted by update time.
  static List<AnyCodingTaskItem> buildUnifiedTaskList({
    required List<SessionInfo> activeSessions,
    required List<RecentSession> recentSessions,
    List<OfflinePendingAction> offlinePendingActions = const [],
    Set<String> pinnedKeys = const {},
    Map<String, CodexTakeoverQueueStatusMessage> takeoverQueueByThread = const {},
  }) {
    final items = <AnyCodingTaskItem>[];
    final seenActiveSessionIds = <String>{};

    // 1. Process active sessions (highest priority)
    for (final s in activeSessions) {
      // In AnyCoding brand mode, hide Claude sessions
      if (s.provider == 'claude') continue;

      final queueStatus = takeoverQueueByThread[s.id] ??
          (s.claudeSessionId != null ? takeoverQueueByThread[s.claudeSessionId!] : null);
      final category = classifySessionInfo(s, takeoverQueueStatus: queueStatus);
      final provider = resolveProvider(s.provider);
      final projectName = extractProjectShortName(s.projectPath);
      final title = formatTaskTitle(
        name: s.name,
        firstPrompt: s.lastMessage.isNotEmpty ? s.lastMessage : s.name ?? '',
        summary: s.name,
      );
      final rawStatus = s.status;
      final statusLabel = statusLabelForCategory(
        category,
        rawStatus,
        takeoverQueueStatus: queueStatus,
      );
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
      final statusLabel = '离线排队中';

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

      final queueStatus = takeoverQueueByThread[r.sessionId];
      final category = (queueStatus != null && queueStatus.status == 'queued')
          ? AnyCodingTaskCategory.takeoverQueued
          : classifyRecentSession(r);
      final provider = resolveProvider(r.provider);
      final projectName = extractProjectShortName(r.projectPath);
      final title = formatTaskTitle(
        name: r.name,
        firstPrompt: r.firstPrompt,
        summary: r.summary,
        lastPrompt: r.lastPrompt,
      );
      final rawStatus = category == AnyCodingTaskCategory.completed
          ? 'completed'
          : (category == AnyCodingTaskCategory.takeoverQueued ? 'queued' : 'failed');
      final statusLabel = statusLabelForCategory(
        category,
        rawStatus,
        takeoverQueueStatus: queueStatus,
      );
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

    // 4. Stable sort by pinned first, then updatedAt descending (latest first)
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      final aTime = a.updatedAt;
      final bTime = b.updatedAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

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

  /// Extracts unique projects from sessions and history, fully normalized and deduplicated.
  static List<({String path, String name, int activeCount, int totalCount})> buildProjectSummaries({
    required List<AnyCodingTaskItem> allTasks,
    required Iterable<String> projectPaths,
    Iterable<String> bridgeProjectHistory = const [],
  }) {
    final map = <String, ({String path, String name, int activeCount, int totalCount})>{};

    void recordPath(String rawPath, {bool isActive = false, bool isTask = false, String? explicitName}) {
      final path = normalizeProjectPath(rawPath);
      if (path.isEmpty) return;
      final activeInc = isActive ? 1 : 0;
      final totalInc = isTask ? 1 : 0;
      final current = map[path];
      if (current == null) {
        map[path] = (
          path: path,
          name: explicitName ?? extractProjectShortName(path),
          activeCount: activeInc,
          totalCount: totalInc,
        );
      } else {
        map[path] = (
          path: path,
          name: current.name.isNotEmpty && current.name != '未命名项目'
              ? current.name
              : (explicitName ?? extractProjectShortName(path)),
          activeCount: current.activeCount + activeInc,
          totalCount: current.totalCount + totalInc,
        );
      }
    }

    for (final task in allTasks) {
      recordPath(task.projectPath, isActive: task.isActive, isTask: true, explicitName: task.projectName);
      if (task.worktreePath != null && task.worktreePath!.isNotEmpty) {
        recordPath(task.worktreePath!, isActive: task.isActive, isTask: false);
      }
      if (task.activeSession?.projectPath != null && task.activeSession!.projectPath.isNotEmpty) {
        recordPath(task.activeSession!.projectPath, isActive: true, isTask: false);
      }
      if (task.recentSession?.projectPath != null && task.recentSession!.projectPath.isNotEmpty) {
        recordPath(task.recentSession!.projectPath, isActive: false, isTask: false);
      }
      if (task.recentSession?.resumeCwd != null && task.recentSession!.resumeCwd!.isNotEmpty) {
        recordPath(task.recentSession!.resumeCwd!, isActive: false, isTask: false);
      }
    }

    for (final rawPath in projectPaths) {
      recordPath(rawPath, isActive: false, isTask: false);
    }

    for (final rawPath in bridgeProjectHistory) {
      recordPath(rawPath, isActive: false, isTask: false);
    }

    return map.values.toList();
  }
}
