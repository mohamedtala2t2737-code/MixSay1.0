import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';

/// Flat five-slot bottom bar: Home, Messages, create post, Notifications,
/// Profile. The create button used to float above an arch cut into the middle
/// of the bar; it is now an ordinary item in that same centre slot, so the bar
/// is completely flat. A symmetric `Row` means the items mirror automatically
/// when the app switches to RTL.
class MixSayBottomBar extends StatelessWidget {
  const MixSayBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
    this.unreadCount = 0,
  });

  static const barHeight = 68.0;

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    // The label under each icon needs room to grow with the system text scale.
    final slotHeight = MediaQuery.textScalerOf(context).scale(barHeight);

    final items = <_NavItem>[
      _NavItem(
        icon: Icons.home_filled,
        label: s.home,
        selected: currentIndex == 0,
        onTap: () => onSelect(0),
      ),
      _NavItem(
        icon: Icons.mail_outline_rounded,
        label: s.messages,
        selected: currentIndex == 1,
        onTap: () => onSelect(1),
      ),
      // Not a tab: it opens the composer and never takes a selected state, so
      // the four tab indices stay 0..3 for the shell.
      _NavItem(
        icon: Icons.add_rounded,
        label: s.createPost,
        selected: false,
        onTap: onCreate,
      ),
      _NavItem(
        icon: Icons.notifications_none_rounded,
        label: s.notifications,
        selected: currentIndex == 2,
        onTap: () => onSelect(2),
        badge: unreadCount,
      ),
      _NavItem(
        icon: Icons.account_circle_outlined,
        label: s.profile,
        selected: currentIndex == 3,
        onTap: () => onSelect(3),
      ),
    ];

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: SizedBox(
            height: slotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final item in items) Expanded(child: item)],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge.count(
                count: badge,
                isLabelVisible: badge > 0,
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
