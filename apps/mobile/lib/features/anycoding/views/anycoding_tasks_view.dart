import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../services/task_status_classifier.dart';

class AnyCodingTasksView extends StatefulWidget {
  final List<SessionInfo> activeSessions;
  final List<RecentSession> recentSessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final Set<String> pinnedKeys;
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
  final ValueChanged<RecentSession> onArchiveSession;
  final ValueChanged<String> onStopSession;
  final VoidCallback onRefresh;

  const AnyCodingTasksView({
    super.key,
    required this.activeSessions,
    required this.recentSessions,
    this.offlinePendingActions = const [],
    this.pinnedKeys = const {},
    required this.onNewTask,
    required this.onTapRunning,
    required this.onResumeRecentSession,
    required this.onArchiveSession,
    required this.onStopSession,
    required this.onRefresh,
  });

  @override
  State<AnyCodingTasksView> createState() => _AnyCodingTasksViewState();
}

class _AnyCodingTasksViewState extends State<AnyCodingTasksView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  AnyCodingEngineFilter _engineFilter = AnyCodingEngineFilter.all;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  final _categories = const [
    AnyCodingTaskCategory.inProgress,
    AnyCodingTaskCategory.pending,
    AnyCodingTaskCategory.completed,
    AnyCodingTaskCategory.failed,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final allTasks = TaskStatusClassifier.buildUnifiedTaskList(
      activeSessions: widget.activeSessions,
      recentSessions: widget.recentSessions,
      offlinePendingActions: widget.offlinePendingActions,
      pinnedKeys: widget.pinnedKeys,
    );

    // Compute counts per category
    final countInProgress = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.inProgress)
        .length;
    final countPending = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.pending)
        .length;
    final countCompleted = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.completed)
        .length;
    final countFailed = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.failed)
        .length;

    final counts = [
      countInProgress,
      countPending,
      countCompleted,
      countFailed,
    ];

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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索任务标题、指令或项目名...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text(
                '任务中心',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, size: 20),
            tooltip: _isSearching ? '取消搜索' : '搜索任务',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            tooltip: '新建任务',
            onPressed: widget.onNewTask,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              // 4 Category Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: BrandConfig.codexAccent,
                indicatorWeight: 3,
                labelColor: isDark ? BrandConfig.codexAccent : cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: List.generate(_categories.length, (idx) {
                  final cat = _categories[idx];
                  final cnt = counts[idx];
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.label),
                        if (cnt > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _badgeColorForCategory(cat, cs),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              cnt > 99 ? '99+' : '$cnt',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ),

              // Engine Filter Pills
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _EngineFilterChip(
                        label: '全部',
                        isSelected: _engineFilter == AnyCodingEngineFilter.all,
                        onTap: () => setState(() => _engineFilter = AnyCodingEngineFilter.all),
                      ),
                      const SizedBox(width: 6),
                      _EngineFilterChip(
                        label: 'Codex',
                        icon: Icons.bolt,
                        accentColor: BrandConfig.codexAccent,
                        isSelected: _engineFilter == AnyCodingEngineFilter.codex,
                        onTap: () => setState(() => _engineFilter = AnyCodingEngineFilter.codex),
                      ),
                      const SizedBox(width: 6),
                      _EngineFilterChip(
                        label: 'Antigravity',
                        icon: Icons.auto_awesome,
                        accentColor: BrandConfig.antigravityAccent,
                        isSelected: _engineFilter == AnyCodingEngineFilter.antigravity,
                        onTap: () => setState(() => _engineFilter = AnyCodingEngineFilter.antigravity),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((category) {
          final filtered = TaskStatusClassifier.filterTasks(
            tasks: allTasks,
            category: category,
            engineFilter: _engineFilter,
            query: _searchQuery,
          );

          if (filtered.isEmpty) {
            return _EmptyTaskState(
              category: category,
              isSearching: _searchQuery.isNotEmpty,
              onNewTask: widget.onNewTask,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => widget.onRefresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final task = filtered[index];
                return _TaskListItem(
                  key: ValueKey('anycoding_task_${task.id}'),
                  task: task,
                  onTap: () => _openTask(task),
                  onArchive: task.recentSession != null
                      ? () => widget.onArchiveSession(task.recentSession!)
                      : null,
                  onStop: task.isActive ? () => widget.onStopSession(task.id) : null,
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _badgeColorForCategory(AnyCodingTaskCategory category, ColorScheme cs) {
    switch (category) {
      case AnyCodingTaskCategory.inProgress:
        return const Color(0xFF3B82F6);
      case AnyCodingTaskCategory.pending:
        return const Color(0xFFF59E0B);
      case AnyCodingTaskCategory.completed:
        return const Color(0xFF10B981);
      case AnyCodingTaskCategory.failed:
        return cs.error;
    }
  }

  void _openTask(AnyCodingTaskItem task) {
    if (task.activeSession != null) {
      final s = task.activeSession!;
      widget.onTapRunning(
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
        widget.onTapRunning(
          r.sessionId,
          projectPath: r.projectPath,
          gitBranch: r.gitBranch,
          worktreePath: r.resumeCwd,
          provider: Provider.codex.value,
        );
      } else {
        widget.onResumeRecentSession(r);
      }
    }
  }
}

class _EngineFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _EngineFilterChip({
    required this.label,
    this.icon,
    this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final color = accentColor ?? (isDark ? BrandConfig.codexAccent : cs.primary);
    final bgColor = isSelected
        ? color.withValues(alpha: isDark ? 0.2 : 0.12)
        : (isDark ? BrandConfig.anyCodingCardDark : cs.surfaceContainerLow);
    final borderColor = isSelected
        ? color
        : (isDark ? BrandConfig.anyCodingBorderDark : cs.outlineVariant.withValues(alpha: 0.3));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: isSelected ? color : cs.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskListItem extends StatelessWidget {
  final AnyCodingTaskItem task;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onStop;

  const _TaskListItem({
    super.key,
    required this.task,
    required this.onTap,
    this.onArchive,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surface;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    Color trackColor;
    switch (task.category) {
      case AnyCodingTaskCategory.inProgress:
        trackColor = const Color(0xFF3B82F6);
        break;
      case AnyCodingTaskCategory.pending:
        trackColor = const Color(0xFFF59E0B);
        break;
      case AnyCodingTaskCategory.completed:
        trackColor = const Color(0xFF10B981);
        break;
      case AnyCodingTaskCategory.failed:
        trackColor = const Color(0xFFEF4444);
        break;
    }

    Widget content = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Status Rail Track
            Container(
              width: 4,
              color: trackColor,
            ),
            // Main Content Area
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Engine Badge + Project Name + Status Pill
                      Row(
                        children: [
                          _EnginePill(provider: task.provider),
                          const SizedBox(width: 6),
                          Expanded(
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
                                  color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(category: task.category, label: task.statusLabel),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Task Title
                      Text(
                        task.title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),

                      // Footer metadata + Next Action Pill
                      Row(
                        children: [
                          if (task.gitBranch != null && task.gitBranch!.isNotEmpty) ...[
                            Icon(Icons.fork_right, size: 12, color: cs.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(
                              task.gitBranch!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            task.updatedAt != null ? _formatRelativeTime(task.updatedAt!) : '刚刚',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                          const Spacer(),
                          // Action Button based on category
                          if (task.category == AnyCodingTaskCategory.inProgress) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '进入会话',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3B82F6)),
                                ),
                              ),
                            ),
                            if (onStop != null) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.redAccent),
                                tooltip: '停止任务',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: onStop,
                              ),
                            ],
                          ] else if (task.category == AnyCodingTaskCategory.pending) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '立即处理',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                                ),
                              ),
                            ),
                          ] else if (task.category == AnyCodingTaskCategory.completed) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '查看/追问',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                                ),
                              ),
                            ),
                            if (onArchive != null) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.archive_outlined, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                                tooltip: '归档任务',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: onArchive,
                              ),
                            ],
                          ] else if (task.category == AnyCodingTaskCategory.failed) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '查看报错',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onArchive != null) {
      content = Slidable(
        key: ValueKey('slidable_${task.id}'),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => onArchive!(),
              backgroundColor: const Color(0xFF6B7280),
              foregroundColor: Colors.white,
              icon: Icons.archive_outlined,
              label: '归档',
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
        child: content,
      );
    }

    return content;
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

class _EnginePill extends StatelessWidget {
  final Provider provider;

  const _EnginePill({required this.provider});

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

class _StatusPill extends StatelessWidget {
  final AnyCodingTaskCategory category;
  final String label;

  const _StatusPill({required this.category, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color color;
    switch (category) {
      case AnyCodingTaskCategory.inProgress:
        color = const Color(0xFF3B82F6);
        break;
      case AnyCodingTaskCategory.pending:
        color = const Color(0xFFF59E0B);
        break;
      case AnyCodingTaskCategory.completed:
        color = const Color(0xFF10B981);
        break;
      case AnyCodingTaskCategory.failed:
        color = cs.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _EmptyTaskState extends StatelessWidget {
  final AnyCodingTaskCategory category;
  final bool isSearching;
  final VoidCallback onNewTask;

  const _EmptyTaskState({
    required this.category,
    required this.isSearching,
    required this.onNewTask,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String title;
    String desc;
    IconData icon;

    if (isSearching) {
      title = '未找到匹配任务';
      desc = '尝试更换搜索关键词或重置筛选条件';
      icon = Icons.search_off_rounded;
    } else {
      switch (category) {
        case AnyCodingTaskCategory.inProgress:
          title = '暂无进行中任务';
          desc = '启动新的 Codex 或 Antigravity 任务即可在此监控';
          icon = Icons.play_circle_outline;
          break;
        case AnyCodingTaskCategory.pending:
          title = '暂无待处理事项';
          desc = '所有审批、问题和任务均处于正常状态';
          icon = Icons.check_circle_outline;
          break;
        case AnyCodingTaskCategory.completed:
          title = '暂无已完成任务';
          desc = '完成后的历史任务将展示在这里';
          icon = Icons.task_alt;
          break;
        case AnyCodingTaskCategory.failed:
          title = '暂无失败任务';
          desc = '没有发生错误的异常任务记录';
          icon = Icons.sentiment_satisfied_alt;
          break;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (!isSearching && category == AnyCodingTaskCategory.inProgress) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onNewTask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建任务', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
