import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/brand_config.dart';
import '../models/messages.dart';
import '../services/bridge_service.dart';
import '../features/anycoding/services/task_status_classifier.dart';
import 'rename_session_dialog.dart';

/// Tappable session name in the AppBar. Shows session name or project name.
/// Tap to rename via dialog.
class SessionNameTitle extends StatelessWidget {
  final String sessionId;
  final String? projectPath;
  final Provider? provider;

  const SessionNameTitle({
    super.key,
    required this.sessionId,
    this.projectPath,
    this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final bridge = context.read<BridgeService>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<List<SessionInfo>>(
      stream: bridge.sessionList,
      initialData: bridge.sessions,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        final session = sessions.where((s) => s.id == sessionId).firstOrNull;
        final name = session?.name;
        final fallback = projectPath != null && projectPath!.isNotEmpty
            ? TaskStatusClassifier.extractProjectShortName(projectPath!)
            : '';
        final displayName = name != null && name.isNotEmpty ? name : fallback;
        final resolvedProvider = session != null
            ? TaskStatusClassifier.resolveProvider(session.provider)
            : (provider ?? Provider.codex);

        if (!BrandConfig.isAnyCoding) {
          return GestureDetector(
            onTap: () async {
              final newName = await showRenameSessionDialog(
                context,
                currentName: name,
              );
              if (newName == null || !context.mounted) return;
              bridge.renameSession(
                sessionId: sessionId,
                name: newName.isEmpty ? null : newName,
              );
            },
            child: Text(
              name != null && name.isNotEmpty ? name : fallback,
              style: TextStyle(
                fontSize: 14,
                color: name != null && name.isNotEmpty
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        final isAntigravity = resolvedProvider == Provider.antigravity;
        final accentColor = isAntigravity ? BrandConfig.antigravityAccent : BrandConfig.codexAccent;

        return GestureDetector(
          onTap: () async {
            final newName = await showRenameSessionDialog(
              context,
              currentName: name,
            );
            if (newName == null || !context.mounted) return;
            bridge.renameSession(
              sessionId: sessionId,
              name: newName.isEmpty ? null : newName,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isAntigravity ? 'Antigravity' : 'Codex',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
