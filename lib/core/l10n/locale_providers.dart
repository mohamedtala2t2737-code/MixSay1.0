import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/prefs/startup_preferences.dart';

/// null means "follow the device locale".
class LocaleController extends Notifier<Locale?> {
  static const _prefsKey = StartupPreferences.localeKey;
  static const _systemValue = 'system';

  /// The stored value is read before `runApp`, so the first frame is already
  /// in the right language instead of flashing the device locale.
  @override
  Locale? build() => ref.read(startupPreferencesProvider).locale;

  void setLocale(Locale locale) {
    state = locale;
    _write(locale.languageCode);
  }

  void useSystemLocale() {
    state = null;
    _write(_systemValue);
  }

  void toggle(Locale currentEffective) {
    setLocale(
      currentEffective.languageCode == 'ar'
          ? const Locale('en')
          : const Locale('ar'),
    );
  }

  void _write(String value) {
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.setString(_prefsKey, value);
        })
        .catchError((Object error) {
          debugPrint('Unable to save the locale: $error');
        });
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
