import 'dart:async';
import 'package:flutter/material.dart';
import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/anycoding_logo.dart';
import '../services/task_status_classifier.dart';
import '../widgets/anycoding_new_task_sheet.dart';

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

    // 3. Project summaries
    final projectSummaries = TaskStatusClassifier.buildProjectSummaries(
      allTasks: allTasks,
      projectPaths: projectPaths,
    );

    return Scaffold(
      backgroundColor: isDark
          ? BrandConfig.anyCodingSurfaceDark
          : cs.surfaceContainerLowest,
      appBar: AppBar(
        titleSpacing: 16,
        elevation: 0,
        backgroundColor: isDark
            ? BrandConfig.anyCodingPrimaryDark
            : cs.surface,
        title: Row(
          children: [
            const AnyCodingLogo(size: 26, showContainer: true),
            const SizedBox(width: 8),
            Text(
              BrandConfig.appName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            // Mac Online / Offline Status Pill
            _MacStatusPill(
              isConnected: isConnected,
              bridgeLabel: connectedBridgeLabel ?? BrandConfig.defaultBridgeName,
              onReconnect: onConnect,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新状态',
            onPressed: onRefresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            // Prominent "New Task" Action Bar
            _NewTaskHeroButton(
              onTap: onNewTask,
            ),
            const SizedBox(height: 16),

            // SECTION 1: 待处理 (Needs Attention) - Priority 1
            _SectionHeader(
              title: '待处理事项',
              icon: Icons.notification_important_rounded,
              badgeCount: pendingTasks.length,
              badgeColor: const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 8),
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
              _CompactEmptyCard(
                icon: Icons.check_circle_outline,
                message: '暂无待处理事项，所有任务正常运行',
              ),

            const SizedBox(height: 18),

            // SECTION 2: 进行中任务 (In Progress) - Priority 2
            _SectionHeader(
              title: '进行中任务',
              icon: Icons.play_circle_filled_rounded,
              badgeCount: inProgressTasks.length,
              badgeColor: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 8),
            if (inProgressTasks.isNotEmpty)
              ...inProgressTasks.map(
                (task) => _InProgressTaskCard(
                  task: task,
                  onTap: () => _openTask(task),
                  onStop: () => onStopSession(task.id),
                ),
              )
            else
              _CompactEmptyCard(
                icon: Icons.hourglass_empty_rounded,
                message: '当前没有进行中的任务',
                actionLabel: '新建任务',
                onAction: onNewTask,
              ),

            const SizedBox(height: 18),

            // SECTION 3: 常用项目 (Recent Projects Quick Launch)
            _SectionHeader(
              title: '常用项目',
              icon: Icons.folder_special_rounded,
              badgeCount: projectSummaries.length,
            ),
            const SizedBox(height: 8),
            if (projectSummaries.isNotEmpty)
              ...projectSummaries.take(3).map(
                (proj) => _ProjectQuickLaunchCard(
                  project: proj,
                  onLaunchCodex: () => _launchProject(proj.path, Provider.codex),
                  onLaunchAntigravity: () => _launchProject(proj.path, Provider.antigravity),
                ),
              )
            else
              _CompactEmptyCard(
                icon: Icons.create_new_folder_outlined,
                message: '暂无最近项目',
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
      onResumeRecentSession(task.recentSession!);
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
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
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
          color: cs.error.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.error.withValues(alpha: 0.5)),
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

class _NewTaskHeroButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewTaskHeroButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF0284C7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0284C7).withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '新建 AI 任务',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '选择项目并由 Codex 或 Antigravity 执行',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int? badgeCount;
  final Color? badgeColor;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.badgeCount,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        if (badgeCount != null && badgeCount! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: badgeColor ?? cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$badgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

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
        : cs.surfaceContainerLow;
    final borderColor = isFailed
        ? cs.error.withValues(alpha: 0.6)
        : const Color(0xFFF59E0B).withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EngineBadge(provider: task.provider),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.projectName,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isFailed ? cs.error.withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isFailed ? cs.error : const Color(0xFFD97706),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (task.pendingPermission != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '请求执行工具: ${task.pendingPermission!.toolName}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                    ),
                  ),
                  if (onReject != null)
                    OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('拒绝', style: TextStyle(fontSize: 11)),
                    ),
                  const SizedBox(width: 6),
                  if (onApprove != null)
                    FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('允许', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
        : cs.surfaceContainerLow;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _EngineBadge(provider: task.provider),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      task.projectName,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
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
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (task.gitBranch != null && task.gitBranch!.isNotEmpty) ...[
                    Icon(Icons.fork_right, size: 12, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      task.gitBranch!,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    task.updatedAt != null ? _formatRelativeTime(task.updatedAt!) : '刚刚',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.redAccent),
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

class _ProjectQuickLaunchCard extends StatelessWidget {
  final ({String path, String name, int activeCount, int totalCount}) project;
  final VoidCallback onLaunchCodex;
  final VoidCallback onLaunchAntigravity;

  const _ProjectQuickLaunchCard({
    required this.project,
    required this.onLaunchCodex,
    required this.onLaunchAntigravity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surfaceContainerLow;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (project.activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${project.activeCount} 活跃',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            TaskStatusClassifier.formatMiddleEllipsisPath(project.path, maxLength: 36),
            style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLaunchCodex,
                  icon: const Icon(Icons.bolt, size: 14, color: BrandConfig.codexAccent),
                  label: const Text('启动 Codex', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLaunchAntigravity,
                  icon: const Icon(Icons.auto_awesome, size: 14, color: BrandConfig.antigravityAccent),
                  label: const Text('启动 Antigravity', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _CompactEmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CompactEmptyCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? BrandConfig.anyCodingCardDark.withValues(alpha: 0.5) : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? BrandConfig.anyCodingBorderDark.withValues(alpha: 0.4) : cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
