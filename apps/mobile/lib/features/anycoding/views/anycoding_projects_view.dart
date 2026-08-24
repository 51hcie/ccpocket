import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/directory_browser_sheet.dart' show showDirectoryBrowserSheet;
import '../services/task_status_classifier.dart';

class AnyCodingProjectsView extends StatefulWidget {
  final List<SessionInfo> activeSessions;
  final List<RecentSession> recentSessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final Set<String> projectPaths;
  final BridgeService bridge;
  final void Function(String projectPath, Provider provider) onLaunchProject;
  final ValueChanged<String> onSelectProject;

  const AnyCodingProjectsView({
    super.key,
    required this.activeSessions,
    required this.recentSessions,
    this.offlinePendingActions = const [],
    required this.projectPaths,
    required this.bridge,
    required this.onLaunchProject,
    required this.onSelectProject,
  });

  @override
  State<AnyCodingProjectsView> createState() => _AnyCodingProjectsViewState();
}

class _AnyCodingProjectsViewState extends State<AnyCodingProjectsView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _browseDirectory() async {
    final selected = await showDirectoryBrowserSheet(
      context: context,
      bridge: widget.bridge,
    );

    if (selected != null && selected.isNotEmpty && mounted) {
      widget.onLaunchProject(selected, Provider.codex);
    }
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
    );

    var projectSummaries = TaskStatusClassifier.buildProjectSummaries(
      allTasks: allTasks,
      projectPaths: widget.projectPaths,
    );

    final trimmedQuery = _searchQuery.trim().toLowerCase();
    if (trimmedQuery.isNotEmpty) {
      projectSummaries = projectSummaries.where((p) {
        return p.name.toLowerCase().contains(trimmedQuery) ||
            p.path.toLowerCase().contains(trimmedQuery);
      }).toList();
    }

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
                  hintText: '搜索项目名称或路径...',
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
                '项目',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, size: 20),
            tooltip: _isSearching ? '取消搜索' : '搜索项目',
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
            icon: const Icon(Icons.folder_open, size: 20),
            tooltip: '浏览添加目录',
            onPressed: _browseDirectory,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: projectSummaries.isEmpty
          ? _EmptyProjectsView(
              isSearching: _searchQuery.isNotEmpty,
              onBrowse: _browseDirectory,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: projectSummaries.length,
              itemBuilder: (context, index) {
                final project = projectSummaries[index];
                return _ProjectListItem(
                  key: ValueKey('anycoding_project_${project.path}'),
                  project: project,
                  onLaunchCodex: () => widget.onLaunchProject(project.path, Provider.codex),
                  onLaunchAntigravity: () => widget.onLaunchProject(project.path, Provider.antigravity),
                );
              },
            ),
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final ({String path, String name, int activeCount, int totalCount}) project;
  final VoidCallback onLaunchCodex;
  final VoidCallback onLaunchAntigravity;

  const _ProjectListItem({
    super.key,
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TaskStatusClassifier.formatMiddleEllipsisPath(project.path, maxLength: 36),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (project.totalCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    project.activeCount > 0
                        ? '${project.activeCount} 活跃 / ${project.totalCount} 任务'
                        : '${project.totalCount} 任务',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Two direct launch action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onLaunchCodex,
                  icon: const Icon(Icons.bolt, size: 16, color: BrandConfig.codexAccent),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('启动 Codex', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onLaunchAntigravity,
                  icon: const Icon(Icons.auto_awesome, size: 16, color: BrandConfig.antigravityAccent),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('启动 Antigravity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

class _EmptyProjectsView extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onBrowse;

  const _EmptyProjectsView({
    required this.isSearching,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off_rounded : Icons.folder_open_rounded,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              isSearching ? '未找到匹配项目' : '暂无项目记录',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching ? '请尝试其他关键词' : '可通过浏览 Mac 目录或新建任务添加项目',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('浏览 Mac 目录添加', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
