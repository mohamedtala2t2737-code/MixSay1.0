import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/prefs/startup_preferences.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  static const _prefsKey = StartupPreferences.themeModeKey;

  /// Read before `runApp` so the first frame already uses the saved theme.
  @override
  ThemeMode build() => ref.read(startupPreferencesProvider).themeMode;

  void setMode(ThemeMode mode) {
    state = mode;
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setString(_prefsKey, mode.name);
        })
        .catchError((Object error) {
          debugPrint('Unable to save the theme mode: $error');
        });
  }

  void toggle() {
    setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
