import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/bridge_service.dart';
import '../../../services/bridge_route_selector.dart';

class AnyCodingRoutesCard extends StatelessWidget {
  const AnyCodingRoutesCard({super.key, required this.bridge});
  final BridgeService bridge;

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: bridge.routeChanges,
    builder: (context, _) {
      final active = bridge.lastUrl == null
          ? null
          : BridgeRouteSelector.origin(bridge.lastUrl!);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '多通道连接',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('route_refresh_button'),
                    tooltip: '重新检测通道',
                    onPressed: bridge.refreshRoutes,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                bridge.routes.reason,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final entry in bridge.routes.latency.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        entry.key == active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: entry.key == active
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${Uri.parse(entry.key).host.contains(':') ? 'IPv6 地址' : 'IPv4 / 主机地址'} · ${entry.key == active ? '当前使用 · ' : ''}${entry.value == null ? '暂不可达 / 未验证' : '${entry.value} ms'}',
                            ),
                            SelectableText(
                              entry.key,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '复制地址',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: entry.key),
                          );
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制连接地址')),
                            );
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '自动检测可达性与延迟；IPv6 地址不代表移动网络已实测可达。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
