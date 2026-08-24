import 'dart:convert';

import '../constants/brand_config.dart';
import '../l10n/app_localizations.dart';
import 'messages.dart';

/// Tabs available in the new session sheet.
enum NewSessionTab {
  codex('codex', 'Codex'),
  antigravity('antigravity', 'Antigravity'),
  claude('claude', 'Claude');

  final String value;
  final String label;
  const NewSessionTab(this.value, this.label);

  /// Convert to [Provider].
  Provider toProvider() => switch (this) {
    NewSessionTab.claude => Provider.claude,
    NewSessionTab.codex => Provider.codex,
    NewSessionTab.antigravity => Provider.antigravity,
  };

  /// Look up a tab by its wire-format value.
  static NewSessionTab? fromValue(String value) {
    for (final tab in values) {
      if (tab.value == value) return tab;
    }
    return null;
  }
}

enum EnabledAgentsMode { both, codex, claude, all }

extension NewSessionTabL10n on NewSessionTab {
  String localizedLabel(AppLocalizations l) => switch (this) {
    NewSessionTab.codex => l.newSessionTabCodex,
    NewSessionTab.antigravity => 'Antigravity',
    NewSessionTab.claude => l.newSessionTabClaudeCode,
  };
}

/// Default tab order when no user preference is saved.
const defaultNewSessionTabs = [
  NewSessionTab.codex,
  NewSessionTab.antigravity,
  NewSessionTab.claude,
];

/// Returns the visible tabs for new sessions based on branding.
/// In AnyCoding mode, only [NewSessionTab.codex] and [NewSessionTab.antigravity]
/// are exposed.
List<NewSessionTab> resolveVisibleNewSessionTabs({
  List<NewSessionTab> configuredTabs = defaultNewSessionTabs,
  bool isAnyCoding = BrandConfig.isAnyCoding,
}) {
  if (isAnyCoding) {
    final filtered =
        configuredTabs.where((t) => t != NewSessionTab.claude).toList();
    if (!filtered.contains(NewSessionTab.codex)) {
      filtered.insert(0, NewSessionTab.codex);
    }
    if (!filtered.contains(NewSessionTab.antigravity)) {
      filtered.add(NewSessionTab.antigravity);
    }
    return filtered;
  }
  return configuredTabs;
}

EnabledAgentsMode enabledAgentsModeFromTabs(List<NewSessionTab> tabs) {
  final set = tabs.toSet();
  final hasCodex = set.contains(NewSessionTab.codex);
  final hasClaude = set.contains(NewSessionTab.claude);
  final hasAntigravity = set.contains(NewSessionTab.antigravity);
  if (hasCodex && hasClaude && hasAntigravity) return EnabledAgentsMode.all;
  if (hasCodex && !hasClaude && !hasAntigravity) return EnabledAgentsMode.codex;
  if (hasClaude && !hasCodex && !hasAntigravity) return EnabledAgentsMode.claude;
  return EnabledAgentsMode.both;
}

List<NewSessionTab> tabsForEnabledAgentsMode(
  EnabledAgentsMode mode,
  List<NewSessionTab> current,
) {
  switch (mode) {
    case EnabledAgentsMode.all:
      return const [
        NewSessionTab.codex,
        NewSessionTab.antigravity,
        NewSessionTab.claude,
      ];
    case EnabledAgentsMode.both:
      final ordered = [
        for (final tab in current)
          if (NewSessionTab.values.contains(tab)) tab,
      ];
      final set = ordered.toSet();
      if (!set.contains(NewSessionTab.codex)) {
        ordered.add(NewSessionTab.codex);
      }
      if (!set.contains(NewSessionTab.claude)) {
        ordered.add(NewSessionTab.claude);
      }
      return ordered;
    case EnabledAgentsMode.codex:
      return const [NewSessionTab.codex];
    case EnabledAgentsMode.claude:
      return const [NewSessionTab.claude];
  }
}

bool isNewSessionTabEnabled(
  List<NewSessionTab> enabledTabs,
  NewSessionTab tab,
) {
  return enabledTabs.contains(tab);
}

/// Serialize a tab list to a JSON string for SharedPreferences.
String tabsToJson(List<NewSessionTab> tabs) =>
    jsonEncode(tabs.map((t) => t.value).toList());

/// Deserialize a JSON string to a tab list.
/// Returns null if the JSON is invalid or the result is empty.
List<NewSessionTab>? tabsFromJson(String json) {
  try {
    final list = (jsonDecode(json) as List).cast<String>();
    final tabs = list
        .map(NewSessionTab.fromValue)
        .whereType<NewSessionTab>()
        .toList();
    return tabs.isEmpty ? null : tabs;
  } catch (_) {
    return null;
  }
}
