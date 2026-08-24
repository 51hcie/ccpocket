import 'package:flutter/material.dart';

import '../../models/messages.dart';
import '../../theme/app_theme.dart';
import '../codex_environment_summary.dart';

class SystemChip extends StatelessWidget {
  final SystemMessage message;
  const SystemChip({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isInit = message.subtype == 'init' || message.subtype == 'session_created';

    // Completely suppress empty/raw system init bubbles for Antigravity & generic providers
    if (isInit) {
      if (message.provider == 'codex') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Chip(
              label: CodexEnvironmentSummary(
                leadingLabel: 'Session started',
                model: message.model,
                reasoningEffort: message.modelReasoningEffort,
                approvalPolicy: message.approvalPolicy,
                approvalsReviewer: message.approvalsReviewer,
                sandboxMode: message.sandboxMode,
                showDefaultReasoning: true,
              ),
              backgroundColor: appColors.systemChip,
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      }
      // For Antigravity or general init, hide completely
      return const SizedBox.shrink();
    }

    final subtypeLabel = switch (message.subtype) {
      'compact_boundary' => '上下文已压缩',
      'tool_use' => '工具调用',
      'error' => '系统异常',
      _ => '系统: ${message.subtype}',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Chip(
          label: Text(subtypeLabel, style: const TextStyle(fontSize: 12)),
          backgroundColor: appColors.systemChip,
          side: BorderSide.none,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
