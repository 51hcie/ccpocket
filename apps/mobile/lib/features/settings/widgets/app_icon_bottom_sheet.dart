import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_icon.dart';
import '../../../widgets/workspace_pane_chrome.dart';

Future<void> showAppIconBottomSheet({
  required BuildContext context,
  required AppIconVariant current,
  required ValueChanged<AppIconVariant> onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    constraints: macOSModalBottomSheetConstraints(context),
    showDragHandle: true,
    builder: (ctx) => _AppIconBottomSheetContent(
      current: current,
      onChanged: onChanged,
    ),
  );
}

class _AppIconBottomSheetContent extends StatelessWidget {
  const _AppIconBottomSheetContent({
    required this.current,
    required this.onChanged,
  });

  final AppIconVariant current;
  final ValueChanged<AppIconVariant> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.appIconPickerTitle,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              l.appIconPickerSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final option in AppIconVariant.values) ...[
              _AppIconOptionTile(
                key: ValueKey('app_icon_option_${option.id}'),
                option: option,
                isSelected: option == current,
                title: _titleForOption(l, option),
                subtitle: _subtitleForOption(l, option),
                onTap: () {
                  Navigator.of(context).pop();
                  onChanged(option);
                },
              ),
              if (option != AppIconVariant.values.last)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  String _titleForOption(AppLocalizations l, AppIconVariant option) {
    return switch (option) {
      AppIconVariant.defaultIcon => l.appIconOptionDefaultTitle,
      AppIconVariant.lightOutline => l.appIconOptionLightOutlineTitle,
      AppIconVariant.proCopperEmerald => l.appIconOptionCopperEmeraldTitle,
    };
  }

  String _subtitleForOption(AppLocalizations l, AppIconVariant option) {
    return switch (option) {
      AppIconVariant.defaultIcon => l.appIconOptionDefaultSubtitle,
      AppIconVariant.lightOutline => l.appIconOptionLightOutlineSubtitle,
      AppIconVariant.proCopperEmerald => l.appIconOptionCopperEmeraldSubtitle,
    };
  }
}

class _AppIconOptionTile extends StatelessWidget {
  const _AppIconOptionTile({
    super.key,
    required this.option,
    required this.isSelected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppIconVariant option;
  final bool isSelected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.65)
          : cs.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  option.previewAssetPath,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off_outlined,
                color: isSelected ? cs.primary : cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
