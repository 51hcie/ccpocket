import 'package:flutter/material.dart';
import '../../../constants/brand_config.dart';

class AnyCodingBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final int activeTaskCount;
  final int pendingTaskCount;

  const AnyCodingBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.activeTaskCount = 0,
    this.pendingTaskCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final navBgColor = isDark
        ? BrandConfig.anyCodingPrimaryDark
        : cs.surface;
    final navBorderColor = isDark
        ? BrandConfig.anyCodingBorderDark.withValues(alpha: 0.6)
        : cs.outlineVariant.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(
          top: BorderSide(color: navBorderColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(
                index: 0,
                currentIndex: currentIndex,
                label: '控制台',
                icon: Icons.space_dashboard_outlined,
                activeIcon: Icons.space_dashboard,
                onTap: () => onTabSelected(0),
              ),
              _NavItem(
                index: 1,
                currentIndex: currentIndex,
                label: '任务',
                icon: Icons.task_alt_outlined,
                activeIcon: Icons.task_alt,
                badgeCount: activeTaskCount + pendingTaskCount,
                badgeColor: pendingTaskCount > 0
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF3B82F6),
                onTap: () => onTabSelected(1),
              ),
              _NavItem(
                index: 2,
                currentIndex: currentIndex,
                label: '项目',
                icon: Icons.folder_outlined,
                activeIcon: Icons.folder,
                onTap: () => onTabSelected(2),
              ),
              _NavItem(
                index: 3,
                currentIndex: currentIndex,
                label: '设置',
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                onTap: () => onTabSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == currentIndex;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final selectedColor = isDark
        ? BrandConfig.codexAccent
        : cs.primary;
    final unselectedColor = cs.onSurfaceVariant.withValues(alpha: 0.65);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? selectedColor.withValues(alpha: isDark ? 0.16 : 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      size: 22,
                      color: isSelected ? selectedColor : unselectedColor,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -2,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor ?? const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? selectedColor : unselectedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
