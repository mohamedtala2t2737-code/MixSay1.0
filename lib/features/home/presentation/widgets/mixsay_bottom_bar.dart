import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';

/// Flat five-slot bottom bar: Home, Messages, create post, Notifications,
/// Profile. Icons only — the name of each tab is a `Tooltip`, and screen
/// readers still announce it. The create button used to float above an arch cut
/// into the middle of the bar; it is now an ordinary item in that same centre
/// slot, so the bar is completely flat. A symmetric `Row` means the items mirror
/// automatically when the app switches to RTL.
class MixSayBottomBar extends StatelessWidget {
  const MixSayBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
    this.unreadCount = 0,
  });

  /// An icon-only bar: 56 is the height Material gives a plain bottom bar, and
  /// nothing in it grows with the system text scale any more.
  static const barHeight = 56.0;

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

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

    // Black and edgeless: the shell sets `extendBody: true` so the feed scrolls
    // underneath this bar, and each tab leaves [barHeight] of bottom clearance
    // so nothing sits permanently behind it.
    return Material(
      color: AppColors.navBar,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final item in items) Expanded(child: item)],
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
    // The bar is black whatever theme the rest of the app uses, so its icons
    // take the fixed pair rather than the scheme's muted gray, which would
    // disappear on black in a light theme.
    final color = selected
        ? AppColors.navIconSelected
        : AppColors.navIconUnselected;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Badge.count(
            count: badge,
            isLabelVisible: badge > 0,
            backgroundColor: AppColors.navBadge,
            child: Icon(icon, size: 30, color: color),
          ),
        ),
      ),
    );
  }
}
