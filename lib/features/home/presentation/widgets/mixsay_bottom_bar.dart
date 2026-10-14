import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';

/// Instagram-style bottom bar: an upward arch in the middle, with the create
/// post button floating over the crest. A symmetric `Row` means the four tabs
/// mirror automatically when the app switches to RTL.
class MixSayBottomBar extends StatelessWidget {
  const MixSayBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
    this.unreadCount = 0,
  });

  static const headroom = 18.0;
  static const barHeight = 68.0;
  static const archRise = 16.0;
  static const fabSize = 56.0;

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final tabs = <_NavItem>[
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

    return SizedBox(
      height: headroom + barHeight + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: headroom,
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              painter: _ArchBarPainter(
                color: theme.colorScheme.surface,
                borderColor: theme.dividerColor,
                rise: archRise,
              ),
            ),
          ),
          Positioned(
            top: headroom + archRise,
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tabs[0]),
                Expanded(child: tabs[1]),
                // Symmetric spacer so the FAB always lands on screen centre.
                const SizedBox(width: 96),
                Expanded(child: tabs[2]),
                Expanded(child: tabs[3]),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Tooltip(
                message: s.createPost,
                child: SizedBox(
                  width: fabSize,
                  height: fabSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onCreate,
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat shoulders that arch up to a rounded crest at the horizontal centre.
class _ArchBarPainter extends CustomPainter {
  const _ArchBarPainter({
    required this.color,
    required this.borderColor,
    required this.rise,
  });

  final Color color;
  final Color borderColor;
  final double rise;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final shoulder = math.min(size.width * 0.16, 90.0);
    final path = Path()
      ..moveTo(0, rise)
      ..lineTo(centre - shoulder, rise)
      ..cubicTo(
        centre - shoulder * 0.42,
        rise,
        centre - shoulder * 0.30,
        0,
        centre,
        0,
      )
      ..cubicTo(
        centre + shoulder * 0.30,
        0,
        centre + shoulder * 0.42,
        rise,
        centre + shoulder,
        rise,
      )
      ..lineTo(size.width, rise)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 6, true);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      Path()
        ..moveTo(0, rise)
        ..lineTo(centre - shoulder, rise)
        ..cubicTo(
          centre - shoulder * 0.42,
          rise,
          centre - shoulder * 0.30,
          0,
          centre,
          0,
        )
        ..cubicTo(
          centre + shoulder * 0.30,
          0,
          centre + shoulder * 0.42,
          rise,
          centre + shoulder,
          rise,
        )
        ..lineTo(size.width, rise),
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ArchBarPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.rise != rise;
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
