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
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => AnyCodingMonitoringSheet(
    bridge: bridge,
    monitoringService: monitoringService,
  ),
);

class AnyCodingMonitoringSheet extends StatefulWidget {
  final BridgeService bridge;
  final BridgeMonitoringService? monitoringService;
  const AnyCodingMonitoringSheet({
    super.key,
    required this.bridge,
    this.monitoringService,
  });
  @override
  State<AnyCodingMonitoringSheet> createState() => _MonitoringState();
}

class _MonitoringState extends State<AnyCodingMonitoringSheet> {
  late final BridgeMonitoringService service;
  MonitoringDataModel? data;
  bool loading = true;
  String? error;
  Timer? timer;
  StreamSubscription<void>? routeSubscription;
  int requestGeneration = 0;
  String? pendingUrl;
  String? observedUrl;

  @override
  void initState() {
    super.initState();
    service = widget.monitoringService ?? BridgeMonitoringService();
    load();
    routeSubscription = widget.bridge.routeChanges.listen((_) {
      if (widget.bridge.lastUrl != observedUrl) load(background: true);
    });
    timer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => load(background: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    routeSubscription?.cancel();
    requestGeneration++;
    super.dispose();
  }

  Future<void> load({bool background = false}) async {
    final url = widget.bridge.lastUrl ?? BrandConfig.defaultAnyCodingBridgeUrl;
    if (pendingUrl == url) return;
    observedUrl = widget.bridge.lastUrl;
    pendingUrl = url;
    final generation = ++requestGeneration;
    if (!background && mounted) {
      setState(() => loading = true);
    }
    try {
      final result = await service.fetchMonitoringData(url);
      if (mounted &&
          generation == requestGeneration &&
          url ==
              (widget.bridge.lastUrl ??
                  BrandConfig.defaultAnyCodingBridgeUrl)) {
        setState(() {
          data = result;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted &&
          generation == requestGeneration &&
          url ==
              (widget.bridge.lastUrl ??
                  BrandConfig.defaultAnyCodingBridgeUrl)) {
        setState(() {
          loading = false;
          if (data == null) {
            error = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    } finally {
      if (generation == requestGeneration) pendingUrl = null;
    }
  }

  String uptime(int s) {
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    return d > 0
        ? '$d 天 $h 小时'
        : h > 0
        ? '$h 小时 $m 分'
        : '$m 分钟';
  }

  String bytes(int n) {
    if (n <= 0) return '0 B';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = n.toDouble(), i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${u[i]}';
  }

  String time(String? raw) {
    final d = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    return d == null
        ? '未知'
        : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String compact(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
      ? '${(n / 1000).toStringAsFixed(1)}K'
      : '$n';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    Widget content;
    if (loading && data == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (data == null) {
      content = errorView(context);
    } else {
      content = RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            hero(context, data!),
            const SizedBox(height: 14),
            resources(context, data!.system),
            const SizedBox(height: 14),
            bridgePanel(context, data!.bridge),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'AI 额度与用量',
                    style: AppTypography.titleLarge(context),
                  ),
                ),
                Text('本机真实数据源', style: AppTypography.caption(context)),
              ],
            ),
            const SizedBox(height: 10),
            codexPanel(context, data!.codex),
            const SizedBox(height: 12),
            agyPanel(context, data!.antigravity),
            const SizedBox(height: 14),
            Center(
              child: Text(
                '监控刷新 ${time(data!.timestamp)}',
                style: AppTypography.caption(
                  context,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .94,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF070C12) : const Color(0xFFF3F6FA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            header(context),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget header(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 8, 8),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF11BFA5), Color(0xFF3B82F6)],
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.monitor_heart_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mac 监控台', style: AppTypography.titleLarge(c)),
              Text('主机、任务与 AI 额度', style: AppTypography.caption(c)),
            ],
          ),
        ),
        IconButton(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          onPressed: () => Navigator.pop(c),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
  Widget errorView(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 46,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(height: 12),
          Text('无法连接监控服务', style: AppTypography.titleMedium(c)),
          const SizedBox(height: 6),
          Text(error ?? '未知错误', textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('重新连接'),
          ),
        ],
      ),
    ),
  );

  Widget hero(BuildContext c, MonitoringDataModel d) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0A2B2B), Color(0xFF102A45)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.laptop_mac_rounded, color: Color(0xFF5EEAD4)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.system.hostname,
                style: AppTypography.titleMedium(c, color: Colors.white),
              ),
              Text(
                d.system.os,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(c, color: const Color(0xFFB6C6D6)),
              ),
              const SizedBox(height: 6),
              Text(
                '已运行 ${uptime(d.system.systemUptime)} · Bridge ${d.bridge.port}',
                style: AppTypography.caption(c, color: const Color(0xFF7DD3FC)),
              ),
            ],
          ),
        ),
        status(c, d.bridge.available ? '在线' : '离线', d.bridge.available),
      ],
    ),
  );
  Widget resources(BuildContext c, SystemMetricsModel s) => Row(
    children: [
      Expanded(
        child: resource(
          c,
          'CPU',
          s.cpu.loadPercent,
          '${s.cpu.cores} 核',
          Icons.memory,
          const Color(0xFF2DD4BF),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: resource(
          c,
          '内存',
          s.memory.usedPercent,
          bytes(s.memory.usedBytes),
          Icons.data_usage_rounded,
          const Color(0xFF60A5FA),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: resource(
          c,
          '磁盘',
          s.disk.usedPercent,
          '${bytes(s.disk.freeBytes)} 可用',
          Icons.storage_rounded,
          const Color(0xFFA78BFA),
        ),
      ),
    ],
  );
  Widget resource(
    BuildContext c,
    String label,
    double pct,
    String detail,
    IconData icon,
    Color color,
  ) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 9),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: AppTypography.titleLarge(c),
          ),
          Text(label, style: AppTypography.labelSmall(c)),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: (pct / 100).clamp(0, 1),
            color: color,
            backgroundColor: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(c),
          ),
        ],
      ),
    );
  }

  Widget bridgePanel(BuildContext c, BridgeMetricsModel b) {
    final items = [
      ('运行', b.taskCounts.running, const Color(0xFF2DD4BF)),
      ('排队', b.taskCounts.queued, const Color(0xFFFBBF24)),
      ('完成', b.taskCounts.completed, const Color(0xFF60A5FA)),
      ('失败', b.taskCounts.failed, const Color(0xFFF87171)),
    ];
    return panel(
      c,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          panelHeader(
            c,
            Icons.hub_rounded,
            'Bridge 与任务',
            b.source,
            const Color(0xFF2DD4BF),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: metric(c, '连续运行', uptime(b.uptime))),
              Expanded(child: metric(c, '连接设备', '${b.connectedClients} 台')),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.2,
            children: items
                .map(
                  (x) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: x.$3.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: x.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(x.$1, style: AppTypography.caption(c)),
                        ),
                        Text(
                          '${x.$2}',
                          style: AppTypography.titleMedium(c, color: x.$3),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget codexPanel(BuildContext c, CodexMetricsModel x) => panel(
    c,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        panelHeader(
          c,
          Icons.bolt_rounded,
          'Codex',
          x.source,
          BrandConfig.codexAccent,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: metric(c, '账户', x.account)),
            Expanded(child: metric(c, '套餐', x.plan)),
          ],
        ),
        if (x.fiveHourWindow != null) ...[
          const SizedBox(height: 14),
          used(
            c,
            '5 小时窗口',
            x.fiveHourWindow!.usedPercent,
            x.fiveHourWindow!.resetsAt,
          ),
        ],
        if (x.sevenDayWindow != null) ...[
          const SizedBox(height: 12),
          used(
            c,
            '7 天窗口',
            x.sevenDayWindow!.usedPercent,
            x.sevenDayWindow!.resetsAt,
          ),
        ],
      ],
    ),
  );
  Widget agyPanel(BuildContext c, AntigravityMetricsModel a) => panel(
    c,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        panelHeader(
          c,
          Icons.auto_awesome_rounded,
          'Antigravity',
          a.source,
          BrandConfig.antigravityAccent,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: metric(c, '默认模型', a.model)),
            status(
              c,
              a.status == 'Ready' ? 'CLI 就绪' : a.status,
              a.status == 'Ready',
            ),
          ],
        ),
        if (a.usage != null) ...[
          const SizedBox(height: 12),
          usagePanel(c, a.usage!),
        ],
        const SizedBox(height: 14),
        if (a.accounts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              a.error == null ? a.note : '${a.note}\n${a.error}',
              style: AppTypography.bodySmall(c),
            ),
          )
        else
          ...a.accounts.map(
            (x) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: account(c, x),
            ),
          ),
        Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${a.quota} · 刷新 ${time(a.refreshedAt)}',
                style: AppTypography.caption(c),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget usagePanel(BuildContext c, AntigravityUsageModel usage) {
    final accent = BrandConfig.antigravityAccent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.data_usage_rounded,
                size: 18,
                color: Color(0xFFF97316),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text('Token 用量', style: AppTypography.titleSmall(c)),
              ),
              Text(
                '今日 ${compact(usage.todayTokens)}',
                style: AppTypography.labelSmall(c, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
            children: [
              tokenMetric(c, '累计输入', usage.allInputTokens, Icons.login_rounded),
              tokenMetric(
                c,
                '累计输出',
                usage.allOutputTokens,
                Icons.logout_rounded,
              ),
              tokenMetric(
                c,
                '缓存读取',
                usage.allCacheReadTokens,
                Icons.bolt_rounded,
              ),
              tokenMetric(
                c,
                '推理 Tokens',
                usage.allReasoningTokens,
                Icons.psychology_alt_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: metric(c, '累计 Tokens', compact(usage.allTokens))),
              Expanded(child: metric(c, '累计消息', '${usage.allMessages}')),
              Expanded(child: metric(c, '今日消息', '${usage.todayMessages}')),
            ],
          ),
          if (usage.models.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('模型用量排行', style: AppTypography.labelSmall(c)),
            const SizedBox(height: 7),
            ...usage.models.take(4).map((model) => modelUsageRow(c, model)),
          ],
        ],
      ),
    );
  }

  Widget tokenMetric(BuildContext c, String label, int value, IconData icon) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: BrandConfig.antigravityAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(c),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(compact(value), style: AppTypography.titleSmall(c)),
        ],
      ),
    );
  }

  Widget modelUsageRow(BuildContext c, AntigravityModelUsageModel model) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall(c),
                ),
                Text(
                  '输入 ${compact(model.inputTokens)} · 输出 ${compact(model.outputTokens)} · ${model.messages} 条',
                  style: AppTypography.caption(c),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            compact(model.totalTokens),
            style: AppTypography.titleSmall(
              c,
              color: BrandConfig.antigravityAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget account(BuildContext c, AntigravityAccountQuotaModel a) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_circle_outlined,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(a.account, style: AppTypography.titleSmall(c)),
              ),
              Text('更新 ${time(a.updatedAt)}', style: AppTypography.caption(c)),
            ],
          ),
          const SizedBox(height: 12),
          ...a.groups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: group(c, g),
            ),
          ),
        ],
      ),
    );
  }

  Widget group(BuildContext c, AntigravityQuotaGroupModel g) {
    AntigravityQuotaBucketModel? weekly, short;
    for (final b in g.buckets) {
      if (b.window == 'weekly') weekly = b;
      if (b.window == '5h') short = b;
    }
    final color = g.name.toLowerCase().contains('gemini')
        ? const Color(0xFF60A5FA)
        : const Color(0xFFA78BFA);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(g.name, style: AppTypography.labelSmall(c)),
        const SizedBox(height: 7),
        if (weekly != null)
          remaining(c, '本周剩余', weekly.remainingPercent, weekly.resetsAt, color),
        if (short != null) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              Text('5 小时剩余', style: AppTypography.caption(c)),
              const Spacer(),
              Text(
                '${short.remainingPercent.toStringAsFixed(0)}% · ${time(short.resetsAt)} 重置',
                style: AppTypography.caption(c, color: color),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget remaining(
    BuildContext c,
    String label,
    double pct,
    String reset,
    Color color,
  ) => Column(
    children: [
      Row(
        children: [
          Text(label, style: AppTypography.caption(c)),
          const Spacer(),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: AppTypography.titleSmall(c, color: color),
          ),
        ],
      ),
      const SizedBox(height: 5),
      LinearProgressIndicator(
        value: (pct / 100).clamp(0, 1),
        color: color,
        backgroundColor: color.withValues(alpha: .12),
        minHeight: 7,
        borderRadius: BorderRadius.circular(5),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: Text('${time(reset)} 重置', style: AppTypography.caption(c)),
      ),
    ],
  );
  Widget used(BuildContext c, String label, double pct, String reset) {
    final color = pct >= 85 ? const Color(0xFFF87171) : const Color(0xFFF59E0B);
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: AppTypography.caption(c)),
            const Spacer(),
            Text(
              '${pct.toStringAsFixed(1)}% 已用',
              style: AppTypography.titleSmall(c, color: color),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: (pct / 100).clamp(0, 1),
          color: color,
          backgroundColor: color.withValues(alpha: .12),
          minHeight: 7,
          borderRadius: BorderRadius.circular(5),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${time(reset)} 重置', style: AppTypography.caption(c)),
        ),
      ],
    );
  }

  Widget panel(BuildContext c, Widget child) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .35)),
      ),
      child: child,
    );
  }

  Widget panelHeader(
    BuildContext c,
    IconData icon,
    String title,
    String source,
    Color color,
  ) => Row(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: AppTypography.titleMedium(c))),
      Flexible(
        child: Text(
          source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption(c),
        ),
      ),
    ],
  );
  Widget metric(BuildContext c, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.caption(c)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.titleSmall(c),
      ),
    ],
  );
  Widget status(BuildContext c, String text, bool ok) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (ok ? const Color(0xFF10B981) : const Color(0xFFEF4444))
          .withValues(alpha: .14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: ok ? const Color(0xFF34D399) : const Color(0xFFF87171),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: AppTypography.labelSmall(
            c,
            color: ok ? const Color(0xFF34D399) : const Color(0xFFF87171),
          ),
        ),
      ],
    ),
  );
}
