import 'package:flutter/material.dart';

import '../../../models/messages.dart';
import '../../../theme/provider_style.dart';

/// Dashboard card displaying Mac online status, dual-engine availability,
/// and live task statistics (running, waiting for input, failed, completed).
class DualEngineDashboardCard extends StatelessWidget {
  final BridgeConnectionState connectionState;
  final String? endpointLabel;
  final int runningCount;
  final int waitingCount;
  final int failedCount;
  final int completedCount;
  final String? codexStatusLabel;
  final String? antigravityStatusLabel;
  final bool? isCodexOnline;
  final bool? isAntigravityOnline;
  final bool isCodexAvailable;
  final bool isAntigravityAvailable;

  const DualEngineDashboardCard({
    super.key,
    required this.connectionState,
    this.endpointLabel,
    this.runningCount = 0,
    this.waitingCount = 0,
    this.failedCount = 0,
    this.completedCount = 0,
    this.codexStatusLabel,
    this.antigravityStatusLabel,
    this.isCodexOnline,
    this.isAntigravityOnline,
    this.isCodexAvailable = true,
    this.isAntigravityAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = connectionState == BridgeConnectionState.connected;

    final resolvedCodexStatus = codexStatusLabel ??
        (isConnected && isCodexAvailable ? 'Ready' : 'Offline');
    final resolvedCodexOnline =
        isCodexOnline ?? (isConnected && isCodexAvailable);

    final resolvedAntigravityStatus = antigravityStatusLabel ??
        (isConnected && isAntigravityAvailable ? 'Supported' : 'Offline');
    final resolvedAntigravityOnline =
        isAntigravityOnline ?? (isConnected && isAntigravityAvailable);

    return Container(
      key: const ValueKey('dual_engine_dashboard_card'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? cs.outlineVariant.withValues(alpha: 0.4)
              : cs.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Mac Status & Endpoint
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? const Color(0xFF34C759) : cs.error,
                  boxShadow: isConnected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF34C759).withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Mac Bridge Online' : 'Mac Bridge Offline',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isConnected ? cs.onSurface : cs.error,
                ),
              ),
              const Spacer(),
              if (endpointLabel != null && endpointLabel!.isNotEmpty)
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      endpointLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Dual Engine Badges
          Row(
            children: [
              _EngineBadge(
                provider: Provider.codex,
                name: 'Codex',
                statusText: resolvedCodexStatus,
                isOnline: resolvedCodexOnline,
              ),
              const SizedBox(width: 8),
              _EngineBadge(
                provider: Provider.antigravity,
                name: 'Antigravity',
                statusText: resolvedAntigravityStatus,
                isOnline: resolvedAntigravityOnline,
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Row 3: 4 Task Metric Counters
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Running',
                  count: runningCount,
                  color: const Color(0xFF007AFF),
                  icon: Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricChip(
                  label: 'Waiting',
                  count: waitingCount,
                  color: const Color(0xFFFF9500),
                  icon: Icons.hourglass_top_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricChip(
                  label: 'Failed',
                  count: failedCount,
                  color: const Color(0xFFFF3B30),
                  icon: Icons.error_outline_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricChip(
                  label: 'Done',
                  count: completedCount,
                  color: const Color(0xFF34C759),
                  icon: Icons.check_circle_outline_rounded,
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
  final String name;
  final String statusText;
  final bool isOnline;

  const _EngineBadge({
    required this.provider,
    required this.name,
    required this.statusText,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final style = providerStyleFor(context, provider);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline
            ? style.background
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOnline
              ? style.border
              : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            style.icon,
            size: 13,
            color: isOnline
                ? style.foreground
                : cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 5),
          Text(
            '$name: $statusText',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOnline
                  ? style.foreground
                  : cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _MetricChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: count > 0 ? color : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
