import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/directory_browser_sheet.dart' show showDirectoryBrowserSheet;
import '../../../widgets/new_session_sheet.dart';
import '../services/task_status_classifier.dart';

/// Shows the AnyCoding 4-step New Task sheet:
/// `选择项目 -> 选择引擎 -> 输入任务 -> 启动`
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

  @override
  void initState() {
    super.initState();
    final init = widget.initialParams;
    _selectedProvider = widget.initialProvider ??
        (init?.provider == Provider.antigravity
            ? Provider.antigravity
            : Provider.codex);

    final initialPath = widget.initialProjectPath ??
        init?.projectPath ??
        (widget.recentProjects.isNotEmpty ? widget.recentProjects.first.path : '');

    _projectPath = initialPath;
    _pathController.text = initialPath;

    _selectedCodexModel = init?.model ?? 'gpt-5.4';
    _selectedReasoningEffort = init?.modelReasoningEffort ?? ReasoningEffort.medium;
    _codexPermissionsMode = init?.codexPermissionsMode ?? CodexPermissionsMode.defaultPermissions;

    _loadLastSavedPreferences();
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

    final params = NewSessionParams(
      projectPath: effectivePath,
      provider: _selectedProvider,
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
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final sheetBgColor = isDark
        ? BrandConfig.anyCodingPrimaryDark
        : cs.surface;
    final cardBgColor = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surfaceContainerLow;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      decoration: BoxDecoration(
        color: sheetBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle & Header
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (_selectedProvider == Provider.antigravity
                            ? BrandConfig.antigravityAccent
                            : BrandConfig.codexAccent)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _selectedProvider == Provider.antigravity
                        ? Icons.auto_awesome
                        : Icons.bolt,
                    size: 18,
                    color: _selectedProvider == Provider.antigravity
                        ? BrandConfig.antigravityAccent
                        : BrandConfig.codexAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '新建任务',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Flow Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 1: 选择项目
                  const _SectionTitle(
                    stepNumber: '1',
                    title: '选择项目',
                    subtitle: '在指定代码仓库或目录中启动 AI 任务',
                  ),
                  const SizedBox(height: 8),

                  // Selected Project Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder, size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _projectPath.isNotEmpty
                                    ? TaskStatusClassifier.extractProjectShortName(_projectPath)
                                    : '请选择项目目录',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _projectPath.isNotEmpty
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _browseDirectory,
                              icon: const Icon(Icons.folder_open, size: 16),
                              label: const Text('浏览', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ],
                        ),
                        if (_projectPath.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            TaskStatusClassifier.formatMiddleEllipsisPath(_projectPath, maxLength: 40),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Recent project chips
                  if (widget.recentProjects.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.recentProjects.take(4).map((p) {
                        final isSelected = _projectPath == p.path;
                        return ChoiceChip(
                          label: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) => _selectProject(p.path),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Step 2: 选择引擎
                  const _SectionTitle(
                    stepNumber: '2',
                    title: '选择执行引擎',
                    subtitle: '选择由 Codex (GPT) 还是 Antigravity (Gemini) 执行',
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      // Codex Engine
                      Expanded(
                        child: _EngineSelectCard(
                          name: 'Codex',
                          desc: 'OpenAI 编程代理',
                          icon: Icons.bolt,
                          accentColor: BrandConfig.codexAccent,
                          isSelected: _selectedProvider == Provider.codex,
                          onTap: () => setState(() => _selectedProvider = Provider.codex),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Antigravity Engine
                      Expanded(
                        child: _EngineSelectCard(
                          name: 'Antigravity',
                          desc: 'DeepMind 任务代理',
                          icon: Icons.auto_awesome,
                          accentColor: BrandConfig.antigravityAccent,
                          isSelected: _selectedProvider == Provider.antigravity,
                          onTap: () => setState(() => _selectedProvider = Provider.antigravity),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Step 3: 输入任务
                  const _SectionTitle(
                    stepNumber: '3',
                    title: '输入初始指令',
                    subtitle: '简明描述需要 AI 执行的目标或需求',
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _promptController,
                    maxLines: 3,
                    minLines: 2,
                    decoration: InputDecoration(
                      hintText: '例如: 检查未提交的更改并生成详细代码审查报告...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: cardBgColor,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _selectedProvider == Provider.antigravity
                              ? BrandConfig.antigravityAccent
                              : BrandConfig.codexAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Step 4: 高级选项 (Default Collapsed)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const ValueKey('new_task_advanced_options'),
                      initiallyExpanded: _showAdvancedOptions,
                      onExpansionChanged: (exp) => setState(() => _showAdvancedOptions = exp),
                      tilePadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            '高级选项',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Git Worktree isolation toggle
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('独立 Worktree 分支隔离', style: TextStyle(fontSize: 13)),
                                subtitle: const Text('在单独的工作树分支中执行，不干扰当前工作区', style: TextStyle(fontSize: 11)),
                                value: _useWorktree,
                                onChanged: (v) => setState(() => _useWorktree = v),
                              ),
                              if (_useWorktree) ...[
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _worktreeBranchController,
                                  decoration: InputDecoration(
                                    labelText: '分支名称 (可选)',
                                    labelStyle: const TextStyle(fontSize: 12),
                                    hintText: 'feat/ai-task-branch',
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],

                              if (_selectedProvider == Provider.codex) ...[
                                const SizedBox(height: 10),
                                const Text('权限模式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<CodexPermissionsMode>(
                                  value: _codexPermissionsMode,
                                  isDense: true,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  items: CodexPermissionsMode.values.map((mode) {
                                    return DropdownMenuItem(
                                      value: mode,
                                      child: Text(mode.label, style: const TextStyle(fontSize: 12)),
                                    );
                                  }).toList(),
                                  onChanged: (mode) {
                                    if (mode != null) setState(() => _codexPermissionsMode = mode);
                                  },
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

          // Fixed Launch Action Bar at Bottom
          Container(
            padding: EdgeInsets.fromLTRB(18, 10, 18, 12 + keyboardHeight),
            decoration: BoxDecoration(
              color: sheetBgColor,
              border: Border(top: BorderSide(color: borderColor, width: 1)),
            ),
            child: FilledButton.icon(
              key: const ValueKey('anycoding_launch_task_button'),
              onPressed: _submit,
              icon: Icon(
                _selectedProvider == Provider.antigravity
                    ? Icons.auto_awesome
                    : Icons.play_arrow_rounded,
                size: 20,
              ),
              label: Text(
                '启动 ${_selectedProvider == Provider.antigravity ? "Antigravity" : "Codex"} 任务',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _selectedProvider == Provider.antigravity
                    ? BrandConfig.antigravityAccent
                    : BrandConfig.codexAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String stepNumber;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                stepNumber,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _EngineSelectCard extends StatelessWidget {
  final String name;
  final String desc;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _EngineSelectCard({
    required this.name,
    required this.desc,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isSelected
        ? accentColor.withValues(alpha: isDark ? 0.18 : 0.12)
        : (isDark ? BrandConfig.anyCodingCardDark : cs.surfaceContainerLow);
    final borderColor = isSelected
        ? accentColor
        : (isDark ? BrandConfig.anyCodingBorderDark : cs.outlineVariant.withValues(alpha: 0.35));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? accentColor : cs.onSurface,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, size: 16, color: accentColor),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
