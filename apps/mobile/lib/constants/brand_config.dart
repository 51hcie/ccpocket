import 'package:flutter/material.dart';

/// Centralized brand configuration supporting AnyCoding and upstream CC Pocket.
class BrandConfig {
  const BrandConfig._();

  /// Whether AnyCoding branding is enabled via `--dart-define=ANYCODING_BRAND=true`.
  static const bool isAnyCoding = bool.fromEnvironment(
    'ANYCODING_BRAND',
    defaultValue: false,
  );

  /// Brand display name.
  static String get appName => isAnyCoding ? 'AnyCoding' : 'CC Pocket';

  /// Brand subtitle / tagline.
  static String get appTagline =>
      isAnyCoding ? 'Mac AI 任务控制台' : 'Claude Code Mobile Client';

  /// Default notification title.
  static String get notificationTitle =>
      isAnyCoding ? 'AnyCoding' : 'CC Pocket';

  /// Default bridge display name.
  static String get defaultBridgeName =>
      isAnyCoding ? 'AnyCoding Mac' : 'Macremote';

  /// Short open-source attribution note for settings / about pages.
  static String get openSourceAttribution =>
      isAnyCoding
          ? '基于 MIT 开源项目 CC Pocket 二次开发'
          : 'MIT Licensed Open Source Project';

  /// Product description for About page.
  static String get aboutDescription =>
      isAnyCoding
          ? 'AnyCoding 是用安卓手机远程指挥 Mac 上 Codex 与 Antigravity 的 AI 任务控制台。'
          : 'Claude Code and Codex mobile companion client.';

  /// Whether supporter / monetization features should be visible.
  static bool get showSupporterFeatures => !isAnyCoding;

  /// Whether store review prompt should be visible.
  static bool get showStoreReview => !isAnyCoding;

  /// Whether SNS share / promotion banners should be visible.
  static bool get showSharePromotion => !isAnyCoding;

  /// Primary brand theme colors.
  static const Color anyCodingPrimaryDark = Color(0xFF0F172A);
  static const Color anyCodingSurfaceDark = Color(0xFF0B0F19);
  static const Color anyCodingCardDark = Color(0xFF131C2E);
  static const Color anyCodingBorderDark = Color(0xFF22304C);

  static const Color codexAccent = Color(0xFF00D2B4);
  static const Color antigravityAccent = Color(0xFFFF7A00);
}
