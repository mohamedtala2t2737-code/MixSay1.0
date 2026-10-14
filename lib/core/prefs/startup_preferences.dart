import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The saved language and theme, read once before `runApp` so the very first
/// frame is already correct instead of flashing the system defaults.
class StartupPreferences {
  const StartupPreferences({this.locale, this.themeMode = ThemeMode.system});

  static const localeKey = 'app_locale';
  static const themeModeKey = 'app_theme_mode';

  final Locale? locale;
  final ThemeMode themeMode;

  static Future<StartupPreferences> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final code = preferences.getString(localeKey);
      final themeName = preferences.getString(themeModeKey);
      return StartupPreferences(
        locale: switch (code) {
          'ar' => const Locale('ar'),
          'en' => const Locale('en'),
          _ => null,
        },
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == themeName,
          orElse: () => ThemeMode.system,
        ),
      );
    } catch (error) {
      debugPrint('Unable to read the saved preferences: $error');
      return const StartupPreferences();
    }
  }
}

final startupPreferencesProvider = Provider<StartupPreferences>(
  (ref) => const StartupPreferences(),
);
