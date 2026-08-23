import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../constants/brand_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router/app_router.dart';
import '../../../services/app_update_service.dart';
import '../../../widgets/anycoding_logo.dart';
import '../../../widgets/workspace_pane_chrome.dart';

/// Floating SliverAppBar for the session list screen.
///
/// Hides on scroll-down and snaps back on scroll-up (Material 3
/// enterAlways behaviour).
class SessionListSliverAppBar extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onDisconnect;
  final bool forceElevated;
  final double? toolbarHeight;
  final String? bridgeLabel;

  const SessionListSliverAppBar({
    super.key,
    required this.onTitleTap,
    required this.onDisconnect,
    this.forceElevated = false,
    this.toolbarHeight,
    this.bridgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SliverAppBar(
      floating: true,
      snap: true,
      forceElevated: forceElevated,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      title: GestureDetector(
        onTap: onTitleTap,
        child: _SessionListTitle(
          title: BrandConfig.appName,
          subtitle: bridgeLabel,
        ),
      ),
      actions: [
        IconButton(
          key: const ValueKey('settings_button'),
          icon: Badge(
            isLabelVisible: AppUpdateService.instance.cachedUpdate != null,
            smallSize: 8,
            child: const Icon(Icons.settings),
          ),
          onPressed: () => context.router.navigate(SettingsRoute()),
          tooltip: l.settings,
        ),
        IconButton(
          key: const ValueKey('gallery_button'),
          icon: const Icon(Icons.collections),
          onPressed: () => context.router.navigate(GalleryRoute()),
          tooltip: l.gallery,
        ),
        IconButton(
          key: const ValueKey('disconnect_button'),
          icon: const Icon(Icons.link_off),
          onPressed: onDisconnect,
          tooltip: l.disconnect,
        ),
      ],
    );
  }
}

class SessionListPaneHeader extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenGallery;
  final VoidCallback? onDisconnect;
  final VoidCallback? onTogglePaneVisibility;
  final String? bridgeLabel;

  const SessionListPaneHeader({
    super.key,
    required this.onTitleTap,
    required this.onOpenSettings,
    this.onOpenGallery,
    this.onDisconnect,
    this.onTogglePaneVisibility,
    this.bridgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final openGallery = onOpenGallery;
    final disconnect = onDisconnect;
    final togglePaneVisibility = onTogglePaneVisibility;
    final chrome = resolveWorkspacePaneChrome(
      platform: Theme.of(context).platform,
      isAdaptiveWorkspace: true,
      isLeftPaneVisible: true,
      slot: WorkspacePaneSlot.left,
    );
    final titleStyle = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    final actionGap = chrome.useMacOSAdaptiveChrome ? 8.0 : 0.0;

    return SizedBox(
      height: chrome.toolbarHeight,
      child: Padding(
        padding: chrome.headerPadding(),
        child: Row(
          children: [
            if (!chrome.useMacOSAdaptiveChrome)
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: _SessionListTitle(
                    key: const ValueKey('session_list_pane_title'),
                    title: BrandConfig.appName,
                    subtitle: bridgeLabel,
                    titleStyle: titleStyle,
                  ),
                ),
              )
            else
              const Expanded(
                child: MacOSWindowDragHandle(child: SizedBox.expand()),
              ),
            _PaneHeaderActionButton(
              key: const ValueKey('settings_button'),
              tooltip: l.settings,
              onPressed: onOpenSettings,
              icon: Badge(
                isLabelVisible: AppUpdateService.instance.cachedUpdate != null,
                smallSize: 8,
                child: const Icon(Icons.settings),
              ),
              compact: chrome.useMacOSAdaptiveChrome,
            ),
            if (openGallery != null ||
                disconnect != null ||
                togglePaneVisibility != null) ...[
              if (actionGap > 0) SizedBox(width: actionGap),
              if (openGallery != null)
                _PaneHeaderActionButton(
                  key: const ValueKey('gallery_button'),
                  tooltip: l.gallery,
                  onPressed: openGallery,
                  icon: const Icon(Icons.collections),
                  compact: chrome.useMacOSAdaptiveChrome,
                ),
              if (disconnect != null)
                _PaneHeaderActionButton(
                  key: const ValueKey('disconnect_button'),
                  tooltip: l.disconnect,
                  onPressed: disconnect,
                  icon: const Icon(Icons.link_off),
                  compact: chrome.useMacOSAdaptiveChrome,
                ),
              if (togglePaneVisibility != null)
                _PaneHeaderActionButton(
                  key: const ValueKey('collapse_left_pane_button'),
                  tooltip: l.hideSessions,
                  onPressed: togglePaneVisibility,
                  icon: const Icon(Icons.chevron_left),
                  compact: chrome.useMacOSAdaptiveChrome,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaneHeaderActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final String tooltip;
  final bool compact;

  const _PaneHeaderActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final chrome = resolveWorkspacePaneChrome(
        platform: Theme.of(context).platform,
        isAdaptiveWorkspace: true,
        isLeftPaneVisible: true,
        slot: WorkspacePaneSlot.left,
      );
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: icon,
        style: chrome.compactButtonStyle(),
      );
    }
    return IconButton(onPressed: onPressed, tooltip: tooltip, icon: icon);
  }
}

class _SessionListTitle extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final TextStyle? titleStyle;

  const _SessionListTitle({
    super.key,
    this.title,
    this.subtitle,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTitle =
        (BrandConfig.isAnyCoding || title == null || title!.isEmpty)
            ? BrandConfig.appName
            : title!;
    final subtitle = this.subtitle;
    final theme = Theme.of(context);
    final defaultTitleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    );

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (BrandConfig.isAnyCoding) ...[
          const AnyCodingLogo(size: 22),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            effectiveTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle ?? defaultTitleStyle,
          ),
        ),
      ],
    );

    if (subtitle == null || subtitle.isEmpty) {
      return titleRow;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        const SizedBox(height: 1),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
