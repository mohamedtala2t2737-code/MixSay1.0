import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/prefs/startup_preferences.dart';
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

  testWidgets('the settings sheet switches language and theme', (tester) async {
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

  testWidgets('the settings sheet scrolls instead of clipping at a big scale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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

    // The theme row sits under the fold once the sheet is short and the text
    // is large; before the sheet scrolled it was simply cut off.
    expect(find.text('Dark'), findsOneWidget);
    await tester.ensureVisible(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Dark')).bottom, lessThan(320));
    expect(tester.takeException(), isNull);
  });

  test(
    'the stored language and theme are ready for the very first frame',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_locale': 'ar',
        'app_theme_mode': 'light',
      });
      final container = ProviderContainer(
        overrides: [
          startupPreferencesProvider.overrideWithValue(
            await StartupPreferences.read(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(localeControllerProvider), const Locale('ar'));
      expect(container.read(themeModeProvider), ThemeMode.light);
    },
  );

  test('an unknown stored value falls back to the system theme', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'neon'});
    final container = ProviderContainer(
      overrides: [
        startupPreferencesProvider.overrideWithValue(
          await StartupPreferences.read(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(localeControllerProvider), isNull);
  });
}
