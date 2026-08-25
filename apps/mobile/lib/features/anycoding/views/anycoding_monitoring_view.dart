import 'dart:async';
import 'package:flutter/material.dart';
import '../../../constants/brand_config.dart';
import '../../../services/bridge_monitoring_service.dart';
import '../../../services/bridge_service.dart';
import '../../../theme/app_typography.dart';

Future<void> showAnyCodingMonitoringSheet({
  required BuildContext context,
  required BridgeService bridge,
  BridgeMonitoringService? monitoringService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AnyCodingMonitoringSheet(
      bridge: bridge,
      monitoringService: monitoringService,
    ),
  );
}

class AnyCodingMonitoringSheet extends StatefulWidget {
  final BridgeService bridge;
  final BridgeMonitoringService? monitoringService;

  const AnyCodingMonitoringSheet({
    super.key,
    required this.bridge,
    this.monitoringService,
  });

  @override
  State<AnyCodingMonitoringSheet> createState() =>
      _AnyCodingMonitoringSheetState();
}

class _AnyCodingMonitoringSheetState extends State<AnyCodingMonitoringSheet> {
  late final BridgeMonitoringService _service;
  MonitoringDataModel? _data;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _service = widget.monitoringService ?? BridgeMonitoringService();
    _loadData();
    // Bounded auto-refresh interval (every 8 seconds when active)
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_isLoading) {
        _loadData(isBackground: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final bridgeUrl = widget.bridge.lastUrl ?? 'ws://127.0.0.1:8766';
      final result = await _service.fetchMonitoringData(bridgeUrl);
      if (mounted) {
        setState(() {
          _data = result;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_data == null) {
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '0s';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${seconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark
        ? BrandConfig.anyCodingSurfaceDark
        : cs.surfaceContainerLowest;
    final cardBgColor = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surface;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Drag Handle & Title Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: BrandConfig.codexAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.monitor_heart_rounded,
                      color: isDark
                          ? BrandConfig.codexAccent
                          : const Color(0xFF0D9488),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mac 监控控制台',
                          style: AppTypography.titleLarge(context),
                        ),
                        Text(
                          _data?.system.hostname ?? '实时系统与引擎负载',
                          style: AppTypography.caption(context),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () => _loadData(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),

            // Scrollable Content Cards
            Expanded(
              child: _isLoading && _data == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                  : _errorMessage != null && _data == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 40, color: cs.error),
                                const SizedBox(height: 12),
                                Text(
                                  '无法连接到 Bridge 监控服务',
                                  style: AppTypography.titleMedium(context, color: cs.error),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  style: AppTypography.bodySmall(context),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('重新连接'),
                                  onPressed: () => _loadData(),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          children: [
                            if (_data != null) ...[
                              // 1. Mac System Status Card
                              _buildSystemCard(
                                context,
                                _data!.system,
                                cardBgColor,
                                borderColor,
                              ),
                              const SizedBox(height: 14),

                              // 2. Bridge & Task Status Card
                              _buildBridgeCard(
                                context,
                                _data!.bridge,
                                cardBgColor,
                                borderColor,
                              ),
                              const SizedBox(height: 14),

                              // 3. Codex Engine Quota & Usage Card
                              _buildCodexCard(
                                context,
                                _data!.codex,
                                cardBgColor,
                                borderColor,
                              ),
                              const SizedBox(height: 14),

                              // 4. Antigravity Engine Status Card
                              _buildAntigravityCard(
                                context,
                                _data!.antigravity,
                                cardBgColor,
                                borderColor,
                              ),
                              const SizedBox(height: 14),

                              // Freshness Footer
                              Center(
                                child: Text(
                                  '数据更新于: ${_data!.timestamp.replaceFirst("T", " ").split(".")[0]} · 真实采样',
                                  style: AppTypography.caption(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProvenanceTag(BuildContext context, String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '来源: $source',
        style: AppTypography.caption(context),
      ),
    );
  }

  Widget _buildSystemCard(
    BuildContext context,
    SystemMetricsModel system,
    Color cardBgColor,
    Color borderColor,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.laptop_mac_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Mac 主机系统', style: AppTypography.titleMedium(context)),
                ],
              ),
              _buildProvenanceTag(context, system.source),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '操作系统',
                  value: system.os,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '系统运行时间',
                  value: _formatUptime(system.systemUptime),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // CPU & Memory Gauges
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CPU 负载 (${system.cpu.cores} 核)', style: AppTypography.caption(context)),
                        Text('${system.cpu.loadPercent.toStringAsFixed(1)}%', style: AppTypography.mono(context, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (system.cpu.loadPercent / 100).clamp(0.0, 1.0),
                      color: system.cpu.loadPercent > 80 ? cs.error : cs.primary,
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('内存占用', style: AppTypography.caption(context)),
                        Text('${system.memory.usedPercent.toStringAsFixed(1)}%', style: AppTypography.mono(context, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (system.memory.usedPercent / 100).clamp(0.0, 1.0),
                      color: system.memory.usedPercent > 85 ? cs.error : const Color(0xFF0D9488),
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Disk
          if (system.disk.available) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '系统主磁盘 (${_formatBytes(system.disk.usedBytes)} / ${_formatBytes(system.disk.totalBytes)})',
                  style: AppTypography.caption(context),
                ),
                Text(
                  '剩余 ${_formatBytes(system.disk.freeBytes)}',
                  style: AppTypography.mono(context, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (system.disk.usedPercent / 100).clamp(0.0, 1.0),
              color: system.disk.usedPercent > 90 ? cs.error : const Color(0xFF3B82F6),
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ] else ...[
            Text('磁盘指标: 暂时不可获取', style: AppTypography.caption(context)),
          ],
        ],
      ),
    );
  }

  Widget _buildBridgeCard(
    BuildContext context,
    BridgeMetricsModel bridge,
    Color cardBgColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.router_rounded, size: 20, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text('Bridge 运行时与任务队列', style: AppTypography.titleMedium(context)),
                ],
              ),
              _buildProvenanceTag(context, bridge.source),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'Bridge 连续运行',
                  value: _formatUptime(bridge.uptime),
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '当前活跃客户端',
                  value: '${bridge.connectedClients} 台设备',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Task Counters Grid
          Row(
            children: [
              Expanded(
                child: _buildTaskBadge(
                  context,
                  label: '正在运行',
                  count: bridge.taskCounts.running,
                  color: const Color(0xFF0D9488),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTaskBadge(
                  context,
                  label: '排队待执行',
                  count: bridge.taskCounts.queued,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTaskBadge(
                  context,
                  label: '已完成任务',
                  count: bridge.taskCounts.completed,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTaskBadge(
                  context,
                  label: '失败/中断',
                  count: bridge.taskCounts.failed,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodexCard(
    BuildContext context,
    CodexMetricsModel codex,
    Color cardBgColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 20, color: BrandConfig.codexAccent),
                  const SizedBox(width: 8),
                  Text('Codex 引擎配额', style: AppTypography.titleMedium(context)),
                ],
              ),
              _buildProvenanceTag(context, codex.source),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '授权账户 (已脱敏)',
                  value: codex.account,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '套餐方案',
                  value: codex.plan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (codex.fiveHourWindow != null) ...[
            _buildWindowUsageRow(
              context,
              label: '5 小时速率限制窗口',
              usedPercent: codex.fiveHourWindow!.usedPercent,
              resetsAt: codex.fiveHourWindow!.resetsAt,
            ),
            const SizedBox(height: 8),
          ],
          if (codex.sevenDayWindow != null) ...[
            _buildWindowUsageRow(
              context,
              label: '7 天用量限制窗口',
              usedPercent: codex.sevenDayWindow!.usedPercent,
              resetsAt: codex.sevenDayWindow!.resetsAt,
            ),
          ] else if (codex.fiveHourWindow == null && codex.sevenDayWindow == null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '近期会话尚未返回显式速率窗口事件，随任务发起自动读取',
                      style: AppTypography.caption(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAntigravityCard(
    BuildContext context,
    AntigravityMetricsModel agy,
    Color cardBgColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: BrandConfig.antigravityAccent),
                  const SizedBox(width: 8),
                  Text('Antigravity 引擎', style: AppTypography.titleMedium(context)),
                ],
              ),
              _buildProvenanceTag(context, agy.source),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: '调度默认模型',
                  value: agy.model,
                ),
              ),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'CLI 状态',
                  value: agy.status,
                  valueColor: agy.status == 'Ready' ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('实时配额: ', style: AppTypography.labelSmall(context)),
                    Text(
                      agy.quota,
                      style: AppTypography.mono(context, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  agy.note,
                  style: AppTypography.caption(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowUsageRow(
    BuildContext context, {
    required String label,
    required double usedPercent,
    required String resetsAt,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.caption(context)),
            Text('${usedPercent.toStringAsFixed(1)}% 已用', style: AppTypography.mono(context, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: (usedPercent / 100).clamp(0.0, 1.0),
          color: usedPercent > 80 ? cs.error : const Color(0xFFF97316),
          backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(context)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.titleSmall(context, color: valueColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildTaskBadge(
    BuildContext context, {
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: AppTypography.titleMedium(context, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
