import 'package:flutter/material.dart';
import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/anycoding_logo.dart';
import '../services/task_status_classifier.dart';

class AnyCodingConsoleView extends StatelessWidget {
  final BridgeConnectionState connectionState;
  final String? connectedBridgeLabel;
  final List<SessionInfo> activeSessions;
  final List<RecentSession> recentSessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final Set<String> projectPaths;
  final VoidCallback onNewTask;
  final void Function(
    String sessionId, {
    String? projectPath,
    String? gitBranch,
    String? worktreePath,
    String? provider,
    String? permissionMode,
    String? sandboxMode,
    String? approvalPolicy,
    String? approvalsReviewer,
  }) onTapRunning;
  final ValueChanged<RecentSession> onResumeRecentSession;
  final ValueChanged<String> onStopSession;
  final void Function(String sessionId, String toolUseId, {bool clearContext})? onApprovePermission;
  final void Function(String sessionId, String toolUseId, {String? message})? onRejectPermission;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final BridgeService bridge;
  final void Function(String projectPath, Provider provider)? onQuickLaunchProject;
  final void Function(int tabIndex)? onNavigateTab;

  const AnyCodingConsoleView({
    super.key,
    required this.connectionState,
    this.connectedBridgeLabel,
    required this.activeSessions,
    required this.recentSessions,
    this.offlinePendingActions = const [],
    required this.projectPaths,
    required this.onNewTask,
    required this.onTapRunning,
    required this.onResumeRecentSession,
    required this.onStopSession,
    this.onApprovePermission,
    this.onRejectPermission,
    required this.onRefresh,
    required this.onConnect,
    required this.bridge,
    this.onQuickLaunchProject,
    this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isConnected = connectionState == BridgeConnectionState.connected;

    final allTasks = TaskStatusClassifier.buildUnifiedTaskList(
      activeSessions: activeSessions,
      recentSessions: recentSessions,
      offlinePendingActions: offlinePendingActions,
    );

    // 1. Pending items (waiting for approval, question, or failed requiring action)
    final pendingTasks = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.pending || t.category == AnyCodingTaskCategory.failed)
        .toList();

    // 2. Truly active / in-progress tasks (running or starting or streaming or idle active)
    final inProgressTasks = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.inProgress)
        .toList();

    // 3. Completed tasks count
    final completedCount = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.completed)
        .length;

    // 4. Project summaries
    final projectSummaries = TaskStatusClassifier.buildProjectSummaries(
      allTasks: allTasks,
      projectPaths: projectPaths,
      bridgeProjectHistory: bridge.projectHistory,
    );

    return Scaffold(
      backgroundColor: isDark
          ? BrandConfig.anyCodingSurfaceDark
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 14,
        elevation: 0,
        centerTitle: false,
        backgroundColor: isDark
            ? BrandConfig.anyCodingPrimaryDark
            : Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? BrandConfig.anyCodingBorderDark.withValues(alpha: 0.6)
                : const Color(0xFFE2E8F0),
            height: 1,
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnyCodingLogo(size: 22, showContainer: true),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'AnyCoding',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          _MacStatusPill(
            isConnected: isConnected,
            bridgeLabel: connectedBridgeLabel ?? BrandConfig.defaultBridgeName,
            onReconnect: onConnect,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新状态',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            onPressed: onRefresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('anycoding_console_new_task_fab'),
        onPressed: onNewTask,
        backgroundColor: isDark ? const Color(0xFF00D2B4) : const Color(0xFF0F172A),
        foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          '新建任务',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
          children: [
            // ── Command Center Quick Overview Ribbon ──
            _MetricsRibbon(
              pendingCount: pendingTasks.length,
              inProgressCount: inProgressTasks.length,
              completedCount: completedCount,
              projectCount: projectSummaries.length,
              onTapPending: () => onNavigateTab?.call(1),
              onTapInProgress: () => onNavigateTab?.call(1),
              onTapCompleted: () => onNavigateTab?.call(1),
              onTapProjects: () => onNavigateTab?.call(2),
            ),
            const SizedBox(height: 14),

            // ── SECTION 1: 待处理事项 (Needs Attention) ──
            _SectionHeader(
              title: '待处理事项',
              icon: Icons.notification_important_rounded,
              badgeCount: pendingTasks.length,
              badgeColor: const Color(0xFFF59E0B),
              actionLabel: pendingTasks.isNotEmpty ? '查看全部' : null,
              onAction: pendingTasks.isNotEmpty ? () => onNavigateTab?.call(1) : null,
            ),
            const SizedBox(height: 6),
            if (pendingTasks.isNotEmpty)
              ...pendingTasks.map(
                (task) => _PendingTaskCard(
                  task: task,
                  onTap: () => _openTask(task),
                  onApprove: onApprovePermission != null && task.pendingPermission != null
                      ? () => onApprovePermission!(
                            task.id,
                            task.pendingPermission!.toolUseId,
                          )
                      : null,
                  onReject: onRejectPermission != null && task.pendingPermission != null
                      ? () => onRejectPermission!(
                            task.id,
                            task.pendingPermission!.toolUseId,
                          )
                      : null,
                ),
              )
            else
              const _CompactStatusStrip(
                icon: Icons.check_circle_rounded,
                iconColor: Color(0xFF10B981),
                message: '暂无待处理事项 · 全部任务正常',
              ),

            const SizedBox(height: 16),

            // ── SECTION 2: 正在执行 (Live Tasks & Pipeline) ──
            _SectionHeader(
              title: '正在执行',
              icon: Icons.play_circle_fill_rounded,
              badgeCount: inProgressTasks.length,
              badgeColor: const Color(0xFF3B82F6),
              actionLabel: inProgressTasks.isNotEmpty ? '任务队列' : null,
              onAction: inProgressTasks.isNotEmpty ? () => onNavigateTab?.call(1) : null,
            ),
            const SizedBox(height: 6),
            if (inProgressTasks.isNotEmpty)
              ...inProgressTasks.map(
                (task) => _InProgressTaskCard(
                  task: task,
                  onTap: () => _openTask(task),
                  onStop: () => onStopSession(task.id),
                ),
              )
            else
              _CompactStatusStrip(
                icon: Icons.radio_button_unchecked_rounded,
                iconColor: cs.onSurfaceVariant.withValues(alpha: 0.5),
                message: '当前无运行中任务',
                actionLabel: '+ 新建任务',
                onAction: onNewTask,
              ),

            const SizedBox(height: 16),

            // ── SECTION 3: 常用项目 (Quick Project Hub) ──
            _SectionHeader(
              title: '常用项目',
              icon: Icons.folder_special_rounded,
              badgeCount: projectSummaries.length,
              actionLabel: '浏览库',
              onAction: () => onNavigateTab?.call(2),
            ),
            const SizedBox(height: 6),
            if (projectSummaries.isNotEmpty)
              _HorizontalProjectsList(
                projects: projectSummaries,
                onLaunchCodex: (path) => _launchProject(path, Provider.codex),
                onLaunchAntigravity: (path) => _launchProject(path, Provider.antigravity),
                onBrowseMore: () => onNavigateTab?.call(2),
              )
            else
              const _CompactStatusStrip(
                icon: Icons.create_new_folder_outlined,
                message: '暂无最近项目记录',
              ),
          ],
        ),
      ),
    );
  }

  void _openTask(AnyCodingTaskItem task) {
    if (task.activeSession != null) {
      final s = task.activeSession!;
      onTapRunning(
        s.id,
        projectPath: s.projectPath,
        gitBranch: s.gitBranch,
        worktreePath: s.worktreePath,
        provider: s.provider,
        permissionMode: s.permissionMode,
        sandboxMode: s.codexSandboxMode,
        approvalPolicy: s.codexApprovalPolicy,
        approvalsReviewer: s.codexApprovalsReviewer,
      );
    } else if (task.recentSession != null) {
      final r = task.recentSession!;
      if (r.provider == Provider.codex.value || task.provider == Provider.codex) {
        onTapRunning(
          r.sessionId,
          projectPath: r.projectPath,
          gitBranch: r.gitBranch,
          worktreePath: r.resumeCwd,
          provider: Provider.codex.value,
        );
      } else {
        onResumeRecentSession(r);
      }
    }
  }

  void _launchProject(String path, Provider provider) {
    if (onQuickLaunchProject != null) {
      onQuickLaunchProject!(path, provider);
    } else {
      onNewTask();
    }
  }
}

/// Compact Top Mac Online/Offline Status Pill
class _MacStatusPill extends StatelessWidget {
  final bool isConnected;
  final String bridgeLabel;
  final VoidCallback onReconnect;

  const _MacStatusPill({
    required this.isConnected,
    required this.bridgeLabel,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF10B981),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF10B981),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Mac 在线',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onReconnect,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.error,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '离线 · 点击重连',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4-Segment Metrics Ribbon for instant Command Center state overview
class _MetricsRibbon extends StatelessWidget {
  final int pendingCount;
  final int inProgressCount;
  final int completedCount;
  final int projectCount;
  final VoidCallback? onTapPending;
  final VoidCallback? onTapInProgress;
  final VoidCallback? onTapCompleted;
  final VoidCallback? onTapProjects;

  const _MetricsRibbon({
    required this.pendingCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.projectCount,
    this.onTapPending,
    this.onTapInProgress,
    this.onTapCompleted,
    this.onTapProjects,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : Colors.white;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetricTile(
              label: '待处理',
              count: pendingCount,
              countColor: pendingCount > 0 ? const Color(0xFFF59E0B) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              icon: Icons.warning_amber_rounded,
              highlight: pendingCount > 0,
              onTap: onTapPending,
            ),
          ),
          _MetricDivider(isDark: isDark),
          Expanded(
            child: _MetricTile(
              label: '运行中',
              count: inProgressCount,
              countColor: inProgressCount > 0 ? const Color(0xFF3B82F6) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              icon: Icons.play_arrow_rounded,
              highlight: inProgressCount > 0,
              onTap: onTapInProgress,
            ),
          ),
          _MetricDivider(isDark: isDark),
          Expanded(
            child: _MetricTile(
              label: '已完成',
              count: completedCount,
              countColor: const Color(0xFF10B981),
              icon: Icons.check_circle_outline_rounded,
              highlight: false,
              onTap: onTapCompleted,
            ),
          ),
          _MetricDivider(isDark: isDark),
          Expanded(
            child: _MetricTile(
              label: '项目库',
              count: projectCount,
              countColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              icon: Icons.folder_open_rounded,
              highlight: false,
              onTap: onTapProjects,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  final bool isDark;
  const _MetricDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: isDark
          ? BrandConfig.anyCodingBorderDark.withValues(alpha: 0.7)
          : const Color(0xFFE2E8F0),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int count;
  final Color countColor;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.label,
    required this.count,
    required this.countColor,
    required this.icon,
    required this.highlight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: countColor,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: highlight ? countColor : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified Section Header
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int? badgeCount;
  final Color? badgeColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.badgeCount,
    this.badgeColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Icon(icon, size: 15, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        if (badgeCount != null && badgeCount! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor ?? cs.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$badgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? BrandConfig.codexAccent : cs.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ultra-compact 1-line Status Strip for clean empty states
class _CompactStatusStrip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CompactStatusStrip({
    required this.icon,
    this.iconColor,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark.withValues(alpha: 0.6)
        : Colors.white;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark.withValues(alpha: 0.6)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: iconColor ?? (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? BrandConfig.codexAccent : const Color(0xFF0F766E),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// High-Craft Pending Action Task Card
class _PendingTaskCard extends StatelessWidget {
  final AnyCodingTaskItem task;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _PendingTaskCard({
    required this.task,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final isFailed = task.category == AnyCodingTaskCategory.failed;
    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : Colors.white;
    final borderColor = isFailed
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EngineBadge(provider: task.provider),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.projectName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isFailed
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isFailed ? const Color(0xFFEF4444) : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onTap,
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (task.pendingPermission != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 15, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '请求执行工具: ${task.pendingPermission!.toolName}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
                  if (onReject != null)
                    OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('拒绝', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 6),
                  if (onApprove != null)
                    FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('允许', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bespoke Command Center In-Progress Task Card
class _InProgressTaskCard extends StatelessWidget {
  final AnyCodingTaskItem task;
  final VoidCallback onTap;
  final VoidCallback onStop;

  const _InProgressTaskCard({
    required this.task,
    required this.onTap,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : Colors.white;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header line: Engine badge, project tag, live status indicator
              Row(
                children: [
                  _EngineBadge(provider: task.provider),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.projectName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.statusLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title / prompt summary
              Text(
                task.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // Footer: Branch, relative time, and quick actions
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (task.gitBranch != null && task.gitBranch!.isNotEmpty) ...[
                          Icon(Icons.fork_right_rounded, size: 13, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              task.gitBranch!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          task.updatedAt != null ? _formatRelativeTime(task.updatedAt!) : '刚刚',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Quick Action: Open Chat
                  FilledButton.tonal(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('打开', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  // Quick Action: Stop
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Color(0xFFEF4444)),
                    tooltip: '停止任务',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: onStop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

/// Horizontal Compact Projects Scroll Row
class _HorizontalProjectsList extends StatelessWidget {
  final List<({String path, String name, int activeCount, int totalCount})> projects;
  final ValueChanged<String> onLaunchCodex;
  final ValueChanged<String> onLaunchAntigravity;
  final VoidCallback onBrowseMore;

  const _HorizontalProjectsList({
    required this.projects,
    required this.onLaunchCodex,
    required this.onLaunchAntigravity,
    required this.onBrowseMore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : Colors.white;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : const Color(0xFFE2E8F0);

    return SizedBox(
      height: 104,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: projects.length.clamp(0, 6) + 1,
        itemBuilder: (context, index) {
          if (index == projects.length.clamp(0, 6)) {
            // "Browse All" Tile
            return Container(
              width: 90,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: cardBg.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, style: BorderStyle.solid),
              ),
              child: InkWell(
                onTap: onBrowseMore,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 20, color: isDark ? BrandConfig.codexAccent : const Color(0xFF0F766E)),
                    const SizedBox(height: 4),
                    Text(
                      '查看更多',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? BrandConfig.codexAccent : const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final proj = projects[index];
          return Container(
            width: 170,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 15, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        proj.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  TaskStatusClassifier.formatMiddleEllipsisPath(proj.path, maxLength: 22),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => onLaunchCodex(proj.path),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: BrandConfig.codexAccent.withValues(alpha: isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, size: 12, color: BrandConfig.codexAccent),
                              SizedBox(width: 2),
                              Text(
                                'Codex',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0D9488),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        onTap: () => onLaunchAntigravity(proj.path),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: BrandConfig.antigravityAccent.withValues(alpha: isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: 11, color: BrandConfig.antigravityAccent),
                              SizedBox(width: 2),
                              Text(
                                'AGY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEA580C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Unified Engine Badge (Codex Mint Cyan vs Antigravity Cosmic Orange)
class _EngineBadge extends StatelessWidget {
  final Provider provider;

  const _EngineBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isAntigravity = provider == Provider.antigravity;
    final color = isAntigravity ? BrandConfig.antigravityAccent : BrandConfig.codexAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAntigravity ? Icons.auto_awesome : Icons.bolt, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            isAntigravity ? 'Antigravity' : 'Codex',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: isAntigravity ? const Color(0xFFEA580C) : const Color(0xFF0D9488),
            ),
          ),
        ],
      ),
    );
  }
}
