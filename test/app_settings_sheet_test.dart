import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/theme/theme_providers.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';

Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: child,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('following the device locale renders Arabic right to left', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('ar');
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    late BuildContext captured;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(Directionality.of(captured), TextDirection.rtl);
    expect(AppStrings.of(captured).isArabic, isTrue);
  });

  testWidgets('the settings sheet switches language and theme', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: container.read(localeControllerProvider),
          themeMode: container.read(themeModeProvider),
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [AppSettingsIconButton()]),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Arabic'), findsOneWidget);
    await tester.tap(find.text('Arabic'));
    await tester.pumpAndSettle();
    expect(container.read(localeControllerProvider), const Locale('ar'));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'ar');
    expect(prefs.getString('app_theme_mode'), 'dark');
  });

  test('restore() re-applies the stored language and theme', () async {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'ar',
      'app_theme_mode': 'light',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(localeControllerProvider.notifier).restore();
    await container.read(themeModeProvider.notifier).restore();

    expect(container.read(localeControllerProvider), const Locale('ar'));
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('an unknown stored value falls back to the system theme', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'neon'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).restore();

    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
