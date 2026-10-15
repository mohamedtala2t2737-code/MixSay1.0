import 'package:flutter/material.dart';

import 'package:social_chat/core/theme/app_radius.dart';
import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/theme/app_typography.dart';

/// The flat grey action button the profile header and the follow lists use.
/// [filled] is the stronger variant: the same box with the brand fill, for the
/// action that should stand out on a row.
class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: filled
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: filled
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smBorder),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppTypography.body,
          ),
        ),
      ),
    );
  }
}
