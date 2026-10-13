import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.chatTeal,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.chatTeal,
          secondary: AppColors.chatGreen,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.chatTeal,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.chatTeal,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.chatAccent,
          secondary: AppColors.chatGreen,
          surface: AppColors.darkChatSurface,
        ),
        scaffoldBackgroundColor: AppColors.darkChatBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkChatSurface,
          foregroundColor: AppColors.lightText,
          centerTitle: true,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      );
}
