import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/directory_browser_sheet.dart' show showDirectoryBrowserSheet;
import '../../../widgets/new_session_sheet.dart';
import '../services/task_status_classifier.dart';

/// Shows the AnyCoding V2 Command Composer sheet:
/// Compact project bar -> Segmented Engine Switch -> Focal Prompt Editor -> Collapsed Advanced -> Launch
Future<NewSessionParams?> showAnyCodingNewTaskSheet({
  required BuildContext context,
  required List<({String path, String name})> recentProjects,
  required BridgeService bridge,
  NewSessionParams? initialParams,
  Provider? initialProvider,
  String? initialProjectPath,
}) {
  return showModalBottomSheet<NewSessionParams>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AnyCodingNewTaskSheet(
      recentProjects: recentProjects,
      bridge: bridge,
      initialParams: initialParams,
      initialProvider: initialProvider,
      initialProjectPath: initialProjectPath,
    ),
  );
}

class AnyCodingNewTaskSheet extends StatefulWidget {
  final List<({String path, String name})> recentProjects;
  final BridgeService bridge;
  final NewSessionParams? initialParams;
  final Provider? initialProvider;
  final String? initialProjectPath;

  const AnyCodingNewTaskSheet({
    super.key,
    required this.recentProjects,
    required this.bridge,
    this.initialParams,
    this.initialProvider,
    this.initialProjectPath,
  });

  @override
  State<AnyCodingNewTaskSheet> createState() => _AnyCodingNewTaskSheetState();
}

class _AnyCodingNewTaskSheetState extends State<AnyCodingNewTaskSheet> {
  static const _prefKeyLastSelectedPath = 'anycoding_last_selected_project_path';
  static const _prefKeyLastSelectedEngine = 'anycoding_last_selected_engine';

  late String _projectPath;
  late Provider _selectedProvider;
  final _promptController = TextEditingController();
  final _pathController = TextEditingController();
  bool _showAdvancedOptions = false;
  bool _useWorktree = false;
  final _worktreeBranchController = TextEditingController();
  String? _selectedCodexModel;
  ReasoningEffort? _selectedReasoningEffort;
  CodexPermissionsMode _codexPermissionsMode = CodexPermissionsMode.defaultPermissions;
  late final dynamic _historySub;

  List<({String path, String name})> _computeAllProjects() {
    final map = <String, ({String path, String name})>{};
    for (final p in widget.recentProjects) {
      final norm = TaskStatusClassifier.normalizeProjectPath(p.path);
      if (norm.isEmpty) continue;
      map[norm] = (
        path: norm,
        name: p.name.isNotEmpty ? p.name : TaskStatusClassifier.extractProjectShortName(norm),
      );
    }
    for (final raw in widget.bridge.projectHistory) {
      final norm = TaskStatusClassifier.normalizeProjectPath(raw);
      if (norm.isEmpty || map.containsKey(norm)) continue;
      map[norm] = (
        path: norm,
        name: TaskStatusClassifier.extractProjectShortName(norm),
      );
    }
    return map.values.toList();
  }

  @override
  void initState() {
    super.initState();
    _historySub = widget.bridge.projectHistoryStream.listen((_) {
      if (mounted) setState(() {});
    });
    final init = widget.initialParams;
    _selectedProvider = widget.initialProvider ??
        (init?.provider == Provider.antigravity
            ? Provider.antigravity
            : Provider.codex);

    final allProjects = _computeAllProjects();
    final initialPath = widget.initialProjectPath ??
        init?.projectPath ??
        (allProjects.isNotEmpty ? allProjects.first.path : '');

    _projectPath = initialPath;
    _pathController.text = initialPath;

    _selectedCodexModel = init?.model ?? 'gpt-5.4';
    _selectedReasoningEffort = init?.modelReasoningEffort ?? ReasoningEffort.medium;
    _codexPermissionsMode = init?.codexPermissionsMode ?? CodexPermissionsMode.defaultPermissions;

    _loadLastSavedPreferences();
  }

  @override
  void dispose() {
    _historySub.cancel();
    _promptController.dispose();
    _pathController.dispose();
    _worktreeBranchController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSavedPreferences() async {
    if (widget.initialProjectPath != null || widget.initialParams != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPath = prefs.getString(_prefKeyLastSelectedPath);
      final lastEngine = prefs.getString(_prefKeyLastSelectedEngine);

      if (mounted) {
        setState(() {
          if (lastPath != null && lastPath.isNotEmpty && _projectPath.isEmpty) {
            _projectPath = lastPath;
            _pathController.text = lastPath;
          }
          if (lastEngine != null && widget.initialProvider == null) {
            _selectedProvider = lastEngine == 'antigravity'
                ? Provider.antigravity
                : Provider.codex;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_projectPath.isNotEmpty) {
        await prefs.setString(_prefKeyLastSelectedPath, _projectPath);
      }
      await prefs.setString(
        _prefKeyLastSelectedEngine,
        _selectedProvider == Provider.antigravity ? 'antigravity' : 'codex',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _promptController.dispose();
    _pathController.dispose();
    _worktreeBranchController.dispose();
    super.dispose();
  }

  void _selectProject(String path) {
    setState(() {
      _projectPath = path;
      _pathController.text = path;
    });
  }

  Future<void> _browseDirectory() async {
    final selected = await showDirectoryBrowserSheet(
      context: context,
      bridge: widget.bridge,
      initialPath: _projectPath.isNotEmpty ? _projectPath : null,
    );

    if (selected != null && selected.isNotEmpty && mounted) {
      _selectProject(selected);
    }
  }

  void _submit() {
    final effectivePath = _projectPath.trim();
    if (effectivePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择或输入项目路径')),
      );
      return;
    }

    _savePreferences();

    final promptText = _promptController.text.trim();
    final params = NewSessionParams(
      projectPath: effectivePath,
      provider: _selectedProvider,
      initialPrompt: promptText.isNotEmpty ? promptText : null,
      model: _selectedProvider == Provider.codex ? _selectedCodexModel : null,
      modelReasoningEffort: _selectedProvider == Provider.codex ? _selectedReasoningEffort : null,
      codexPermissionsMode: _codexPermissionsMode,
      useWorktree: _useWorktree,
      worktreeBranch: _useWorktree && _worktreeBranchController.text.trim().isNotEmpty
          ? _worktreeBranchController.text.trim()
          : null,
    );

    Navigator.of(context).pop(params);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isAntigravity = _selectedProvider == Provider.antigravity;
    final activeAccent = isAntigravity ? BrandConfig.antigravityAccent : BrandConfig.codexAccent;

    final sheetBgColor = isDark
        ? BrandConfig.anyCodingPrimaryDark
        : Colors.white;
    final cardBgColor = isDark
        ? BrandConfig.anyCodingCardDark
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : const Color(0xFFE2E8F0);

    return Material(
      color: sheetBgColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Compact Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: activeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isAntigravity ? Icons.auto_awesome : Icons.bolt,
                        size: 16,
                        color: activeAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '指令编辑器',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor),
                      ),
                      child: const Text(
                        'V2',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: borderColor),

              // Scrollable Composer Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Compact Target Project Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _projectPath.isNotEmpty
                                        ? TaskStatusClassifier.extractProjectShortName(_projectPath)
                                        : '选择目标项目目录',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: _browseDirectory,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '浏览',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: cs.primary,
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded, size: 14, color: cs.primary),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_projectPath.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                TaskStatusClassifier.formatMiddleEllipsisPath(_projectPath, maxLength: 42),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Quick Recent Project Chips
                      final allProjects = _computeAllProjects();
                      if (allProjects.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 28,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: allProjects.take(6).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (context, index) {
                              final p = allProjects[index];
                              final isSelected = _projectPath == p.path;
                              return InkWell(
                                onTap: () => _selectProject(p.path),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? cs.primary.withValues(alpha: isDark ? 0.25 : 0.12)
                                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? cs.primary : borderColor,
                                      width: isSelected ? 1.2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected) ...[
                                        Icon(Icons.check_rounded, size: 11, color: cs.primary),
                                        const SizedBox(width: 3),
                                      ],
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          color: isSelected
                                              ? cs.primary
                                              : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),

                      // 2. Segmented Engine Selector
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            // Codex Segment
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _selectedProvider = Provider.codex),
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  decoration: BoxDecoration(
                                    color: !isAntigravity
                                        ? (isDark ? BrandConfig.codexAccent.withValues(alpha: 0.2) : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: !isAntigravity ? BrandConfig.codexAccent : Colors.transparent,
                                      width: 1.2,
                                    ),
                                    boxShadow: !isAntigravity && !isDark
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.bolt,
                                        size: 15,
                                        color: !isAntigravity
                                            ? BrandConfig.codexAccent
                                            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Codex',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: !isAntigravity ? FontWeight.w800 : FontWeight.w600,
                                          color: !isAntigravity
                                              ? (isDark ? BrandConfig.codexAccent : const Color(0xFF0D9488))
                                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'GPT',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Antigravity Segment
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _selectedProvider = Provider.antigravity),
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isAntigravity
                                        ? (isDark ? BrandConfig.antigravityAccent.withValues(alpha: 0.2) : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isAntigravity ? BrandConfig.antigravityAccent : Colors.transparent,
                                      width: 1.2,
                                    ),
                                    boxShadow: isAntigravity && !isDark
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: isAntigravity
                                            ? BrandConfig.antigravityAccent
                                            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Antigravity',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: isAntigravity ? FontWeight.w800 : FontWeight.w600,
                                          color: isAntigravity
                                              ? (isDark ? BrandConfig.antigravityAccent : const Color(0xFFEA580C))
                                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Gemini',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // 3. Focal Command Prompt Editor
                      Container(
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: activeAccent.withValues(alpha: isDark ? 0.5 : 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Composer Inner Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                              child: Row(
                                children: [
                                  Icon(Icons.terminal_rounded, size: 14, color: activeAccent),
                                  const SizedBox(width: 5),
                                  Text(
                                    '指令输入 (Prompt)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    isAntigravity ? 'DeepMind Agent' : 'OpenAI Agent',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: activeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Text Input Area
                            TextField(
                              controller: _promptController,
                              maxLines: 4,
                              minLines: 3,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: '输入 AI 执行指令、代码需求或任务步骤...',
                                hintStyle: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                                filled: false,
                                contentPadding: const EdgeInsets.all(10),
                                border: InputBorder.none,
                              ),
                            ),
                            // Quick Action Chips inside composer
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  _PromptPresetChip(
                                    label: '代码审查',
                                    onTap: () => _promptController.text = '审查最近的改动并指出潜在隐患与改进点',
                                    isDark: isDark,
                                  ),
                                  _PromptPresetChip(
                                    label: '修复报错',
                                    onTap: () => _promptController.text = '分析最近失败的测试用例并进行修复',
                                    isDark: isDark,
                                  ),
                                  _PromptPresetChip(
                                    label: '运行测试',
                                    onTap: () => _promptController.text = '运行所有单元测试并输出报告',
                                    isDark: isDark,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // 4. Collapsible Advanced Options
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const ValueKey('new_task_advanced_options'),
                          initiallyExpanded: _showAdvancedOptions,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          title: Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                '高级选项',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Worktree toggle
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text('独立 Worktree 分支', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    subtitle: const Text('在隔离分支中执行，不影响当前工作区', style: TextStyle(fontSize: 10.5)),
                                    value: _useWorktree,
                                    onChanged: (val) => setState(() => _useWorktree = val),
                                  ),
                                  if (_useWorktree) ...[
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _worktreeBranchController,
                                      style: const TextStyle(fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: '分支名称 (可选)',
                                        labelStyle: const TextStyle(fontSize: 11),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Fixed Bottom Launch Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    key: const ValueKey('anycoding_launch_task_button'),
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: isAntigravity ? BrandConfig.antigravityAccent : BrandConfig.codexAccent,
                      foregroundColor: isAntigravity ? Colors.white : Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isAntigravity ? Icons.auto_awesome : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAntigravity ? '启动 Antigravity 任务' : '启动 Codex 任务',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptPresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _PromptPresetChip({
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '+ $label',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
