import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/brand_config.dart';
import '../../../models/messages.dart';
import '../../../services/bridge_service.dart';
import '../../../services/machine_manager_service.dart';
import '../../../services/macremote_bootstrap_service.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/anycoding_logo.dart';
import '../../settings/state/settings_cubit.dart';
import '../../settings/state/settings_state.dart';
import '../../settings/widgets/app_locale_bottom_sheet.dart';
import '../../settings/widgets/speech_locale_bottom_sheet.dart';
import '../../settings/widgets/theme_bottom_sheet.dart';
import '../widgets/anycoding_update_sheet.dart';
import 'anycoding_monitoring_view.dart';


class AnyCodingSettingsView extends StatelessWidget {
  final bool focusConnection;

  const AnyCodingSettingsView({
    super.key,
    this.focusConnection = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bridge = context.watch<BridgeService>();
    final settingsState = context.watch<SettingsCubit>().state;

    final bgColor = isDark
        ? BrandConfig.anyCodingSurfaceDark
        : cs.surfaceContainerLowest;
    final cardBgColor = isDark
        ? BrandConfig.anyCodingCardDark
        : cs.surface;
    final borderColor = isDark
        ? BrandConfig.anyCodingBorderDark
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        titleSpacing: 16,
        elevation: 0,
        backgroundColor: isDark
            ? BrandConfig.anyCodingPrimaryDark
            : cs.surface,
        title: Text(
          '控制台设置',
          style: AppTypography.titleLarge(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // 1. App Info Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const AnyCodingLogo(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'AnyCoding',
                            style: AppTypography.titleLarge(
                              context,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: BrandConfig.codexAccent.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'V2.0 Command',
                              style: AppTypography.labelSmall(
                                context,
                                color: isDark
                                    ? BrandConfig.codexAccent
                                    : const Color(0xFF0D9488),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '手机上的 AI 项目指挥中心 · 远程调度 Mac',
                        style: AppTypography.caption(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Section: Bridge 主机状态 & 监控
          const _SettingsSectionHeader(title: 'BRIDGE 主机连接与监控'),
          Material(
            color: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.desktop_mac_rounded,
                      size: 20,
                      color: statusColor,
                    ),
                  ),
                  title: Text(
                    'Mac 远程主机 (Bridge)',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    subtitleText,
                    style: AppTypography.caption(context),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: AppTypography.labelSmall(
                            context,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (presetConfig.bridgeUrl != null &&
                    presetConfig.bridgeUrl!.isNotEmpty) ...[
                  Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.settings_backup_restore_rounded,
                      size: 18,
                      color: Color(0xFF00D2B4),
                    ),
                    title: Text(
                      '恢复 AnyCoding 预设连接',
                      style: AppTypography.bodyMedium(context).copyWith(
                        color: const Color(0xFF00D2B4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '预设端点: ${presetConfig.bridgeUrl}',
                      style: AppTypography.caption(context),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      if (!context.mounted) return;
                      final machineManager = context.read<MachineManagerService>();
                      final restoredUrl = await restoreMacremotePresetConnection(
                        prefs: prefs,
                        machineManager: machineManager,
                      );
                      if (restoredUrl != null) {
                        bridge.connect(restoredUrl);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已恢复预设连接并正在连接: $restoredUrl')),
                          );
                        }
                      }
                    },
                  ),
                ],
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_note_rounded, size: 18, color: cs.primary),
                  title: Text(
                    '自定义 Bridge 地址',
                    style: AppTypography.bodyMedium(context),
                  ),
                  subtitle: Text(
                    '修改 Mac 主机 IP / 端口 / 协议',
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showCustomEndpointDialog(context, bridge),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.refresh_rounded, size: 18),
                  title: Text(
                    '重新连接 Bridge',
                    style: AppTypography.bodyMedium(context),
                  ),
                  subtitle: Text(
                    '立即重置退避并连接',
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    bridge.reconnectNow();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已触发 Bridge 重新连接')),
                    );
                  },
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.monitor_heart_rounded, size: 18),
                  title: Text(
                    'Mac 监控控制台 (CPU/内存/磁盘/配额)',
                    style: AppTypography.bodyMedium(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showAnyCodingMonitoringSheet(
                    context: context,
                    bridge: bridge,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. Section: 更新与版本
          const _SettingsSectionHeader(title: '软件更新与版本'),
          Material(
            color: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.system_update_alt_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text(
                    '检查更新 (In-App Bridge Update)',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    '从当前连接的 Mac Bridge 检查并下载更新包',
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showAnyCodingUpdateSheet(
                    context: context,
                    bridge: bridge,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Section: 偏好设置
          const _SettingsSectionHeader(title: '外观与偏好'),
          Material(
            color: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Theme
                ListTile(
                  leading: Icon(
                    Icons.palette_outlined,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text(
                    '主题外观',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    switch (settingsState.themeMode) {
                      ThemeMode.system => '跟随系统',
                      ThemeMode.light => '浅色模式',
                      ThemeMode.dark => '深色模式',
                    },
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showThemeBottomSheet(
                    context: context,
                    current: settingsState.themeMode,
                    onChanged: (mode) =>
                        context.read<SettingsCubit>().setThemeMode(mode),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                // Language
                ListTile(
                  leading: Icon(
                    Icons.language_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text(
                    '界面语言',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    getAppLocaleLabel(context, settingsState.appLocaleId),
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showAppLocaleBottomSheet(
                    context: context,
                    current: settingsState.appLocaleId,
                    onChanged: (id) =>
                        context.read<SettingsCubit>().setAppLocaleId(id),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                // Speech Locale
                ListTile(
                  leading: Icon(
                    Icons.mic_none_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text(
                    '语音输入识别语言',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    getSpeechLocaleLabel(context, settingsState.speechLocaleId),
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showSpeechLocaleBottomSheet(
                    context: context,
                    current: settingsState.speechLocaleId,
                    onChanged: (id) =>
                        context.read<SettingsCubit>().setSpeechLocaleId(id),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 5. Section: 支持引擎
          const _SettingsSectionHeader(title: '调度引擎支持'),
          Material(
            color: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: BrandConfig.codexAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.bolt,
                      size: 18,
                      color: BrandConfig.codexAccent,
                    ),
                  ),
                  title: Text(
                    'Codex (OpenAI)',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    '支持 GPT-5.4 / 思维链 / 本地 Worktree 隔离',
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF10B981),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: BrandConfig.antigravityAccent.withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: BrandConfig.antigravityAccent,
                    ),
                  ),
                  title: Text(
                    'Antigravity (DeepMind)',
                    style: AppTypography.titleSmall(context),
                  ),
                  subtitle: Text(
                    '支持 Gemini 2.5 / 多代理子任务调度',
                    style: AppTypography.caption(context),
                  ),
                  trailing: const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  final String title;

  const _SettingsSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: AppTypography.labelSmall(context),
      ),
    );
  }
}

void _showCustomEndpointDialog(BuildContext context, BridgeService bridge) {
  final controller = TextEditingController(text: bridge.lastUrl ?? '');
  final formKey = GlobalKey<FormState>();

  showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        title: const Text('自定义 Bridge 地址'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '支持 IPv4、IPv6 括号格式、域名以及 ws:// / wss:// 协议：',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Bridge WebSocket URL',
                  hintText: 'ws://192.168.1.100:8765 或 ws://[2408:...]:8766',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return '请输入 Bridge 地址';
                  }
                  final parsed = parseBootstrapEndpoint(val.trim());
                  if (parsed == null) {
                    return '无效的 Bridge 地址格式';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final parsed = parseBootstrapEndpoint(controller.text.trim());
              if (parsed == null) return;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(kPrefKeyBridgeUrl, parsed.wsUrl);

              if (dialogCtx.mounted) {
                final machineManager = context.read<MachineManagerService>();
                await machineManager.recordConnection(
                  host: parsed.host,
                  port: parsed.port,
                  useSsl: parsed.useSsl,
                  name: BrandConfig.isAnyCoding ? 'AnyCoding Mac' : 'Macremote',
                );
              }

              bridge.connect(parsed.wsUrl);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已切换并正在连接: ${parsed.wsUrl}')),
                );
              }
            },
            child: const Text('保存并连接'),
          ),
        ],
      );
    },
  );
}

