import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../constants/brand_config.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/anycoding_logo.dart';
import '../../settings/state/settings_cubit.dart';
import '../../settings/state/settings_state.dart';
import '../../settings/widgets/app_locale_bottom_sheet.dart';
import '../../settings/widgets/speech_locale_bottom_sheet.dart';
import '../../settings/widgets/theme_bottom_sheet.dart';

class AnyCodingSettingsView extends StatelessWidget {
  final bool focusConnection;
  final bool focusSupport;

  const AnyCodingSettingsView({
    super.key,
    this.focusConnection = false,
    this.focusSupport = false,
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
        title: const Text(
          '控制台设置',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
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
                          const Text(
                            'AnyCoding',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: BrandConfig.codexAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'V2.0 Command',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? BrandConfig.codexAccent : const Color(0xFF0D9488),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '手机上的 AI 项目指挥中心 · 远程调度 Mac',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Section: Bridge 主机状态
          const _SettingsSectionHeader(title: 'BRIDGE 主机连接'),
          Container(
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.desktop_mac_rounded, size: 20, color: Color(0xFF10B981)),
                  ),
                  title: const Text(
                    'Mac 远程主机',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Port 8766 · 零配置自动发现',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: Color(0xFF10B981)),
                        SizedBox(width: 4),
                        Text(
                          '已连接',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.refresh_rounded, size: 18),
                  title: const Text('重新连接 Bridge', style: TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    bridge.reconnect();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已触发 Bridge 重新连接')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. Section: 偏好设置
          const _SettingsSectionHeader(title: '外观与偏好'),
          Container(
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                // Theme
                ListTile(
                  leading: Icon(Icons.palette_outlined, size: 20, color: cs.primary),
                  title: const Text('主题外观', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    switch (settingsState.themeMode) {
                      ThemeMode.system => '跟随系统',
                      ThemeMode.light => '浅色模式',
                      ThemeMode.dark => '深色模式',
                    },
                    style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showThemeBottomSheet(
                    context: context,
                    current: settingsState.themeMode,
                    onChanged: (mode) => context.read<SettingsCubit>().setThemeMode(mode),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                // Language
                ListTile(
                  leading: Icon(Icons.language_rounded, size: 20, color: cs.primary),
                  title: const Text('界面语言', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    settingsState.locale?.languageCode == 'zh' ? '简体中文' : '跟随系统',
                    style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showAppLocaleBottomSheet(
                    context: context,
                    current: settingsState.locale,
                    onChanged: (loc) => context.read<SettingsCubit>().setLocale(loc),
                  ),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                // Speech Locale
                ListTile(
                  leading: Icon(Icons.mic_none_rounded, size: 20, color: cs.primary),
                  title: const Text('语音输入识别语言', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    settingsState.speechLocale ?? '自动识别',
                    style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => showSpeechLocaleBottomSheet(
                    context: context,
                    current: settingsState.speechLocale,
                    onChanged: (loc) => context.read<SettingsCubit>().setSpeechLocale(loc),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Section: 支持引擎
          const _SettingsSectionHeader(title: '调度引擎支持'),
          Container(
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: BrandConfig.codexAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.bolt, size: 18, color: BrandConfig.codexAccent),
                  ),
                  title: const Text('Codex (OpenAI)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('支持 GPT-5.4 / 思维链 / 本地 Worktree 隔离', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.check_circle, size: 18, color: Color(0xFF10B981)),
                ),
                Divider(height: 1, indent: 16, endIndent: 16, color: borderColor),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: BrandConfig.antigravityAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.auto_awesome, size: 18, color: BrandConfig.antigravityAccent),
                  ),
                  title: const Text('Antigravity (DeepMind)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('支持 Gemini 2.5 / 多代理子任务调度', style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.check_circle, size: 18, color: Color(0xFF10B981)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
