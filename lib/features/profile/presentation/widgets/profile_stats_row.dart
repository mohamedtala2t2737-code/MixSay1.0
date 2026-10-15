import 'package:flutter/material.dart';

import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/theme/app_typography.dart';

/// One number with the word under it, and the tap that opens its list.
class ProfileStat {
  const ProfileStat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;
}

/// The row of totals under the profile name: posts, followers, following.
///
/// Every column gets the same room, so a five-digit count in one of them never
/// pushes the others off screen, and each line ellipsizes at a large system
/// text scale instead of overflowing.
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final stat in stats) Expanded(child: _Stat(stat: stat))],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.stat});

  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: stat.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stat.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.emphasis,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
