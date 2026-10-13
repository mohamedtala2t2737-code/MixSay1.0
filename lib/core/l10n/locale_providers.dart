import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// null means "follow the device locale".
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void setLocale(Locale locale) => state = locale;

  void toggle(Locale currentEffective) {
    state = currentEffective.languageCode == 'ar'
        ? const Locale('en')
        : const Locale('ar');
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
