import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

/// The outlined partner of [PrimaryButton]: the same box and the same label, with
/// no fill, for the action that must not compete with the main one.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// 48 is `kMinInteractiveDimension`, the height PrimaryButton already paints,
  /// so the two buttons line up in a column without a second number to keep in
  /// sync.
  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = loading || onPressed == null;

    return SizedBox(
      width: double.infinity,
      height: _height,
      child: Opacity(
        opacity: inactive ? 0.6 : 1,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
            textStyle: AppTypography.button,
          ),
          child: loading
              ? const _Spinner()
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18),
                      const SizedBox(width: 8),
                    ],
                    // The label can grow with the system text scale, so it gets
                    // the room the icon does not take rather than a fixed width.
                    Flexible(
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2.2),
  );
}
