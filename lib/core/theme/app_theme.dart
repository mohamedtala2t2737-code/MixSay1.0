import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final background =
        isLight ? AppColors.lightBackground : AppColors.darkBackground;
    final surfaceHigh =
        isLight ? AppColors.lightSurfaceHigh : AppColors.darkSurfaceHigh;
    final onSurface = isLight ? AppColors.textOnLight : AppColors.textOnDark;
    final muted =
        isLight ? AppColors.textMutedOnLight : AppColors.textMutedOnDark;
    final border = isLight ? AppColors.borderOnLight : AppColors.borderOnDark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandPurple,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.brandPurple,
      onPrimary: Colors.white,
      secondary: AppColors.brandPurple,
      onSecondary: Colors.white,
      error: AppColors.error,
      surface: background,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: border,
      surfaceContainerHighest: surfaceHigh,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      // Only the sizes are pinned: the platform default supplies the metrics, so
      // no line of text moves when this theme is adopted.
      textTheme: AppTypography.textTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
