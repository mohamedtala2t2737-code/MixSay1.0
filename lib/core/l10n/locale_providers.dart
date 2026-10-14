import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// null means "follow the device locale".
class LocaleController extends Notifier<Locale?> {
  static const _prefsKey = 'app_locale';
  static const _systemValue = 'system';

  @override
  Locale? build() => null;

  /// Applies the stored choice. The app starts on the device locale until this
  /// completes, so a first-run user never sees a persisted-value delay.
  Future<void> restore() async {
    final code = await _read();
    if (code != null && (code == 'ar' || code == 'en')) state = Locale(code);
  }

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

  Future<String?> _read() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_prefsKey);
    } catch (error) {
      debugPrint('Unable to read the saved locale: $error');
      return null;
    }
  }

  void _write(String value) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefsKey, value);
    }).catchError((Object error) {
      debugPrint('Unable to save the locale: $error');
    });
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
