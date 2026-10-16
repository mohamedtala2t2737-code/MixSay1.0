import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// Optional flat colour; without it the button carries the brand sweep.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final inactive = loading || onPressed == null;
    // Near-black over the sweep stays legible on the cyan and yellow stops,
    // where white would disappear.
    final foreground = color == null ? AppColors.onBrandGradient : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Opacity(
        opacity: inactive ? 0.6 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: color == null ? AppColors.brandGradient : null,
            color: color,
            borderRadius: AppRadius.mdBorder,
          ),
          child: FilledButton(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              // The sweep is painted by the parent so it can fade as a whole.
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: foreground,
              disabledForegroundColor: foreground,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
            ),
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: foreground,
                    ),
                  )
                : Text(label, style: AppTypography.button),
          ),
        ),
      ),
    );
  }
}
