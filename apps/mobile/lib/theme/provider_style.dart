import 'package:flutter/material.dart';

import '../models/messages.dart';

/// Visual tokens for rendering provider-specific labels and badges.
class ProviderStyle {
  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;

  const ProviderStyle({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });
}

ProviderStyle providerStyleFor(BuildContext context, Provider provider) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = switch (provider) {
    Provider.claude => colorScheme.primary,
    Provider.codex =>
      isDark ? const Color(0xFF00D2B4) : const Color(0xFF0D9488),
    Provider.antigravity =>
      isDark ? const Color(0xFFFF7A00) : const Color(0xFFEA580C),
  };

  return ProviderStyle(
    foreground: accent,
    background: accent.withValues(alpha: isDark ? 0.16 : 0.10),
    border: accent.withValues(alpha: isDark ? 0.40 : 0.30),
    icon: switch (provider) {
      Provider.claude => Icons.smart_toy_outlined,
      Provider.codex => Icons.terminal_rounded,
      Provider.antigravity => Icons.auto_awesome_rounded,
    },
  );
}

Provider providerFromRaw(String? provider) =>
    provider == Provider.codex.value
        ? Provider.codex
        : (provider == Provider.antigravity.value
            ? Provider.antigravity
            : Provider.claude);
