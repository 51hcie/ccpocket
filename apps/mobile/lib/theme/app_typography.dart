import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'code_text_style.dart';

/// Centralized AnyCoding Typography Scale & Tokens.
///
/// Eliminates arbitrary one-off font sizes across console, project list,
/// task center, session views, settings, updater, and monitoring console.
/// Normalizes Chinese and English line heights, weights, and rendering.
abstract class AppTypography {
  static const List<String> zhFontFallback = [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  // Standardized line heights
  static const double lineHeightDense = 1.25;
  static const double lineHeightNormal = 1.42;
  static const double lineHeightRelaxed = 1.55;

  // ---------------------------------------------------------------------------
  // Display Tokens: For large numbers, counters, hero headlines
  // ---------------------------------------------------------------------------
  static TextStyle display(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
    double letterSpacing = -0.4,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GoogleFonts.spaceGrotesk(
      fontSize: 26,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: lineHeightDense,
      color: color ?? cs.onSurface,
    );
  }

  static TextStyle displaySmall(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double letterSpacing = -0.2,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GoogleFonts.spaceGrotesk(
      fontSize: 20,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: lineHeightDense,
      color: color ?? cs.onSurface,
    );
  }

  // ---------------------------------------------------------------------------
  // Title Tokens: For section headers, app bars, dialog titles, card titles
  // ---------------------------------------------------------------------------
  static TextStyle titleLarge(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 17,
      fontWeight: fontWeight,
      letterSpacing: -0.2,
      height: lineHeightNormal,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle titleMedium(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 15,
      fontWeight: fontWeight,
      letterSpacing: -0.1,
      height: lineHeightNormal,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle titleSmall(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 13.5,
      fontWeight: fontWeight,
      letterSpacing: 0.0,
      height: lineHeightNormal,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  // ---------------------------------------------------------------------------
  // Body Tokens: For readable chat messages, descriptions, list item details
  // ---------------------------------------------------------------------------
  static TextStyle bodyLarge(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 15,
      fontWeight: fontWeight,
      letterSpacing: 0.15,
      height: lineHeightRelaxed,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle bodyMedium(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 13.5,
      fontWeight: fontWeight,
      letterSpacing: 0.1,
      height: lineHeightNormal,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle bodySmall(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 12,
      fontWeight: fontWeight,
      letterSpacing: 0.1,
      height: lineHeightNormal,
      color: color ?? cs.onSurfaceVariant,
      fontFamilyFallback: zhFontFallback,
    );
  }

  // ---------------------------------------------------------------------------
  // Label Tokens: For action buttons, tabs, chips, form labels
  // ---------------------------------------------------------------------------
  static TextStyle labelLarge(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 13.5,
      fontWeight: fontWeight,
      letterSpacing: 0.1,
      height: lineHeightDense,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle labelMedium(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 12,
      fontWeight: fontWeight,
      letterSpacing: 0.2,
      height: lineHeightDense,
      color: color ?? cs.onSurface,
      fontFamilyFallback: zhFontFallback,
    );
  }

  static TextStyle labelSmall(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 0.5,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 10.5,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: lineHeightDense,
      color: color ?? cs.onSurfaceVariant,
      fontFamilyFallback: zhFontFallback,
    );
  }

  // ---------------------------------------------------------------------------
  // Caption Tokens: For timestamps, secondary metadata, footnotes
  // ---------------------------------------------------------------------------
  static TextStyle caption(
    BuildContext context, {
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 11,
      fontWeight: fontWeight,
      letterSpacing: 0.2,
      height: lineHeightNormal,
      color: color ?? cs.onSurfaceVariant,
      fontFamilyFallback: zhFontFallback,
    );
  }

  // ---------------------------------------------------------------------------
  // Monospace Tokens: For code, file paths, hashes, IP addresses, metric digits
  // ---------------------------------------------------------------------------
  static TextStyle mono(
    BuildContext context, {
    Color? color,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w500,
    double height = 1.35,
  }) {
    final codeSettings = codeTextSettingsOf(context);
    return codeSettings.style(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
    );
  }
}
