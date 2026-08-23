import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';

/// Resolved availability status for an AI engine on the Home dashboard.
enum EngineAvailabilityStatus {
  offline,
  ready,
  supported,
  unavailable,
}

extension EngineAvailabilityStatusX on EngineAvailabilityStatus {
  String get label {
    switch (this) {
      case EngineAvailabilityStatus.offline:
        return 'Offline';
      case EngineAvailabilityStatus.ready:
        return 'Ready';
      case EngineAvailabilityStatus.supported:
        return 'Supported';
      case EngineAvailabilityStatus.unavailable:
        return 'Unavailable';
    }
  }

  bool get isOnline => this != EngineAvailabilityStatus.offline;
}

/// Resolves accurate, non-misleading status for Codex engine.
///
/// When the Bridge is connected, checks if models are loaded.
EngineAvailabilityStatus resolveCodexStatus({
  required bool isConnected,
  required List<String> codexModels,
}) {
  if (!isConnected) {
    return EngineAvailabilityStatus.offline;
  }
  return codexModels.isNotEmpty
      ? EngineAvailabilityStatus.ready
      : EngineAvailabilityStatus.supported;
}

/// Resolves accurate, non-misleading status for Antigravity engine.
///
/// Because the Bridge protocol currently lacks a runtime heartbeat/probe
/// for the host `agy` CLI binary, claiming "Ready" would be hardcoded and
/// misleading. When connected, we return "Supported" to indicate Bridge
/// protocol compatibility without falsely asserting binary readiness.
EngineAvailabilityStatus resolveAntigravityStatus({
  required bool isConnected,
  bool hasProbingSupport = false,
  bool isProbedReady = false,
}) {
  if (!isConnected) {
    return EngineAvailabilityStatus.offline;
  }
  if (hasProbingSupport) {
    return isProbedReady
        ? EngineAvailabilityStatus.ready
        : EngineAvailabilityStatus.unavailable;
  }
  return EngineAvailabilityStatus.supported;
}

/// Pure data class holding the 4 task counters for the home dashboard.
class DashboardTaskCounts {
  final int running;
  final int waiting;
  final int failed;
  final int completed;

  const DashboardTaskCounts({
    required this.running,
    required this.waiting,
    required this.failed,
    required this.completed,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardTaskCounts &&
          runtimeType == other.runtimeType &&
          running == other.running &&
          waiting == other.waiting &&
          failed == other.failed &&
          completed == other.completed;

  @override
  int get hashCode =>
      running.hashCode ^
      waiting.hashCode ^
      failed.hashCode ^
      completed.hashCode;

  @override
  String toString() =>
      'DashboardTaskCounts(running: $running, waiting: $waiting, failed: $failed, completed: $completed)';
}

/// Helper function to determine whether a [RecentSession] is an active session
/// or pending resume action to avoid duplicate counting.
bool isDuplicateRecentSession(
  RecentSession rs, {
  required Iterable<SessionInfo> activeSessions,
  Iterable<OfflinePendingAction> offlinePendingActions = const [],
}) {
  final pendingResumeSessionIds = offlinePendingActions
      .where((action) => action.kind == OfflinePendingActionKind.resume)
      .map((action) => action.sessionId)
      .whereType<String>()
      .toSet();
  if (pendingResumeSessionIds.contains(rs.sessionId)) return true;

  for (final s in activeSessions) {
    if (s.id == rs.sessionId) return true;
    if (s.claudeSessionId != null && s.claudeSessionId == rs.sessionId) {
      return true;
    }
    if (s.provider == rs.provider &&
        s.projectPath == rs.projectPath &&
        s.createdAt == rs.created) {
      return true;
    }
  }
  return false;
}

/// Computes the 4 task status metrics displayed on the Home Dashboard:
/// - Running: active sessions with `status == 'running'` and no pending permissions, plus offline actions.
/// - Waiting: active sessions waiting for input/permission (`pendingPermission != null` or `status == 'waiting_for_input'` or `status == 'waiting_approval'`).
/// - Failed: active sessions with `status == 'failed'` or `status == 'error'`.
/// - Done: non-duplicate historical sessions (`recentSessions`) plus active sessions explicitly `status == 'completed'`.
///
/// CRITICAL: Active sessions with `status == 'idle'` are NOT completed tasks; they are awaiting further user prompts and are omitted from 'Done'.
DashboardTaskCounts calculateDashboardTaskCounts({
  required List<SessionInfo> activeSessions,
  required List<RecentSession> recentSessions,
  List<OfflinePendingAction> offlinePendingActions = const [],
}) {
  final runningCount = activeSessions
          .where((s) => s.status == 'running' && s.pendingPermission == null)
          .length +
      offlinePendingActions.length;

  final waitingCount = activeSessions
      .where(
        (s) =>
            s.pendingPermission != null ||
            s.status == 'waiting_for_input' ||
            s.status == 'waiting_approval',
      )
      .length;

  final failedCount = activeSessions
      .where((s) => s.status == 'failed' || s.status == 'error')
      .length;

  final nonDuplicateRecentCount = recentSessions
      .where(
        (rs) => !isDuplicateRecentSession(
          rs,
          activeSessions: activeSessions,
          offlinePendingActions: offlinePendingActions,
        ),
      )
      .length;

  final completedActiveCount =
      activeSessions.where((s) => s.status == 'completed').length;

  final completedCount = nonDuplicateRecentCount + completedActiveCount;

  return DashboardTaskCounts(
    running: runningCount,
    waiting: waitingCount,
    failed: failedCount,
    completed: completedCount,
  );
}
