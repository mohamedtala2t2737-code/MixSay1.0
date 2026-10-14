import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// The shape of content that has not arrived yet: a face, then a few lines.
///
/// It paints no animation on purpose. A repeating shimmer never settles, and the
/// tests in this app drive every screen with `pumpAndSettle`, so the skeleton
/// that ships has to be a still frame.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.lines = 2, this.avatar = true});

  final int lines;

  /// Whether the row starts with the round placeholder the feed and the
  /// notification list use.
  final bool avatar;

  static const double _barHeight = 12;
  static const double _avatarSize = 42;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.colorScheme.surfaceContainerHighest;

    return Semantics(
      label: AppStrings.of(context).loadingMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (avatar) ...[
              Container(
                width: _avatarSize,
                height: _avatarSize,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in List.generate(lines, (index) => index))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FractionallySizedBox(
                        // The last line of a block is short in every layout the
                        // app already uses, so it reads as text rather than a
                        // stack of identical bars.
                        widthFactor: line == lines - 1 ? 0.6 : 1,
                        child: Container(
                          height: _barHeight,
                          decoration: BoxDecoration(
                            color: tone,
                            borderRadius: AppRadius.chipBorder,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
