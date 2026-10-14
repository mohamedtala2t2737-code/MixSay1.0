import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  static const _prefsKey = 'app_theme_mode';

  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> restore() async {
    String? value;
    try {
      value = (await SharedPreferences.getInstance()).getString(_prefsKey);
    } catch (error) {
      debugPrint('Unable to read the saved theme mode: $error');
      return;
    }
    final stored = ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
    if (stored != state) state = stored;
  }

  void setMode(ThemeMode mode) {
    state = mode;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefsKey, mode.name);
    }).catchError((Object error) {
      debugPrint('Unable to save the theme mode: $error');
    });
  }

  void toggle() {
    setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
