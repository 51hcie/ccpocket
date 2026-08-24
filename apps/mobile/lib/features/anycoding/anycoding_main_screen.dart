import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/messages.dart';
import '../../models/offline_pending_action.dart';
import '../../providers/bridge_cubits.dart';
import '../../providers/machine_manager_cubit.dart';
import '../../services/bridge_service.dart';
import '../../widgets/new_session_sheet.dart' show NewSessionParams;
import '../settings/state/settings_cubit.dart';
import 'services/task_status_classifier.dart';
import 'views/anycoding_console_view.dart';
import 'views/anycoding_tasks_view.dart';
import 'views/anycoding_projects_view.dart';
import 'views/anycoding_settings_view.dart';
import 'widgets/anycoding_bottom_navigation.dart';
import 'widgets/anycoding_new_task_sheet.dart';

class AnyCodingMainScreen extends StatefulWidget {
  final BridgeConnectionState connectionState;
  final String? connectedBridgeLabel;
  final List<SessionInfo> activeSessions;
  final List<RecentSession> recentSessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final Set<String> projectPaths;
  final Set<String> pinnedKeys;
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
  final void Function(String sessionId, String toolUseId, {bool clearContext})? onApprovePermission;
  final void Function(String sessionId, String toolUseId, {String? message})? onRejectPermission;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final ValueChanged<NewSessionParams> onStartNewSession;

  const AnyCodingMainScreen({
    super.key,
    required this.connectionState,
    this.connectedBridgeLabel,
    required this.activeSessions,
    required this.recentSessions,
    this.offlinePendingActions = const [],
    required this.projectPaths,
    this.pinnedKeys = const {},
    required this.onTapRunning,
    required this.onResumeRecentSession,
    required this.onArchiveSession,
    required this.onStopSession,
    this.onApprovePermission,
    this.onRejectPermission,
    required this.onRefresh,
    required this.onConnect,
    required this.onStartNewSession,
  });

  @override
  State<AnyCodingMainScreen> createState() => _AnyCodingMainScreenState();
}

class _AnyCodingMainScreenState extends State<AnyCodingMainScreen> {
  int _currentTab = 0;

  void _switchTab(int index) {
    if (_currentTab != index) {
      setState(() => _currentTab = index);
    }
  }

  Future<void> _openNewTaskSheet({
    Provider? initialProvider,
    String? initialProjectPath,
  }) async {
    final bridge = context.read<BridgeService>();
    final allTasks = TaskStatusClassifier.buildUnifiedTaskList(
      activeSessions: widget.activeSessions,
      recentSessions: widget.recentSessions,
      offlinePendingActions: widget.offlinePendingActions,
    );
    final projectSummaries = TaskStatusClassifier.buildProjectSummaries(
      allTasks: allTasks,
      projectPaths: widget.projectPaths,
    );
    final recentProjectsList = projectSummaries
        .map((p) => (path: p.path, name: p.name))
        .toList();

    final result = await showAnyCodingNewTaskSheet(
      context: context,
      recentProjects: recentProjectsList,
      bridge: bridge,
      initialProvider: initialProvider,
      initialProjectPath: initialProjectPath,
    );

    if (result != null && mounted) {
      widget.onStartNewSession(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = context.read<BridgeService>();

    final allTasks = TaskStatusClassifier.buildUnifiedTaskList(
      activeSessions: widget.activeSessions,
      recentSessions: widget.recentSessions,
      offlinePendingActions: widget.offlinePendingActions,
    );

    final activeCount = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.inProgress)
        .length;
    final pendingCount = allTasks
        .where((t) => t.category == AnyCodingTaskCategory.pending)
        .length;

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentTab != 0) {
          setState(() => _currentTab = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentTab,
          children: [
            // Tab 0: 控制台 (Console)
            AnyCodingConsoleView(
              connectionState: widget.connectionState,
              connectedBridgeLabel: widget.connectedBridgeLabel,
              activeSessions: widget.activeSessions,
              recentSessions: widget.recentSessions,
              offlinePendingActions: widget.offlinePendingActions,
              projectPaths: widget.projectPaths,
              onNewTask: () => _openNewTaskSheet(),
              onTapRunning: widget.onTapRunning,
              onResumeRecentSession: widget.onResumeRecentSession,
              onStopSession: widget.onStopSession,
              onApprovePermission: widget.onApprovePermission,
              onRejectPermission: widget.onRejectPermission,
              onRefresh: widget.onRefresh,
              onConnect: widget.onConnect,
              bridge: bridge,
              onQuickLaunchProject: (path, provider) => _openNewTaskSheet(
                initialProjectPath: path,
                initialProvider: provider,
              ),
            ),

            // Tab 1: 任务中心 (Tasks)
            AnyCodingTasksView(
              activeSessions: widget.activeSessions,
              recentSessions: widget.recentSessions,
              offlinePendingActions: widget.offlinePendingActions,
              pinnedKeys: widget.pinnedKeys,
              onNewTask: () => _openNewTaskSheet(),
              onTapRunning: widget.onTapRunning,
              onResumeRecentSession: widget.onResumeRecentSession,
              onArchiveSession: widget.onArchiveSession,
              onStopSession: widget.onStopSession,
              onRefresh: widget.onRefresh,
            ),

            // Tab 2: 项目 (Projects)
            AnyCodingProjectsView(
              activeSessions: widget.activeSessions,
              recentSessions: widget.recentSessions,
              offlinePendingActions: widget.offlinePendingActions,
              projectPaths: widget.projectPaths,
              bridge: bridge,
              onLaunchProject: (path, provider) => _openNewTaskSheet(
                initialProjectPath: path,
                initialProvider: provider,
              ),
              onSelectProject: (path) => _openNewTaskSheet(initialProjectPath: path),
            ),

            // Tab 3: 设置 (Settings)
            const AnyCodingSettingsView(),
          ],
        ),
        bottomNavigationBar: AnyCodingBottomNavigation(
          currentIndex: _currentTab,
          onTabSelected: _switchTab,
          activeTaskCount: activeCount,
          pendingTaskCount: pendingCount,
        ),
      ),
    );
  }
}
