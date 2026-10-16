import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/core/theme/theme_providers.dart';
import 'package:social_chat/features/profile/presentation/settings_screen.dart';

/// Pumps settings over a router whose routes only report that they were
/// reached, so a test can tell a wired row from a dead one. The app follows the
/// language and theme controllers once the user picks a value, exactly like the
/// real root widget, and starts in the language the test asked for.
Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester,
  Locale locale,
) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      for (final path in ['/settings/saved', '/settings/notifications'])
        GoRoute(
          path: path,
          builder: (context, state) =>
              Scaffold(body: Center(child: Text('reached$path'))),
        ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _App(locale: locale, router: router),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router);
}

class _App extends ConsumerWidget {
  const _App({required this.locale, required this.router});

  final Locale locale;
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      locale: ref.watch(localeControllerProvider) ?? locale,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
    );
  }
}

/// A tall phone so a test can see the whole list at once. The list is lazy, so
/// rows below the fold are not built, and `find.text` would report them missing.
void _useTallViewport(WidgetTester tester, {double height = 2400}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every row of the reference list is here', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('en'));

    expect(find.text('Settings and activity'), findsOneWidget);
    for (final header in [
      'Your account',
      'How you use MixSay',
      'Who can see your content',
      'Support',
    ]) {
      expect(find.text(header), findsOneWidget);
    }
    for (final row in [
      'Account',
      'Language',
      'Appearance',
      'Saved',
      'Archive',
      'Your activity',
      'Notifications',
      'Time management',
      'Account privacy',
      'Blocked',
      'Help',
      'About MixSay',
      'Log out',
    ]) {
      expect(find.text(row), findsOneWidget);
    }
    // The one value the screen can state for real: nothing is private today.
    expect(find.text('Public'), findsOneWidget);
  });

  testWidgets('the search field filters the rows as you type', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.enterText(find.byType(TextField), 'not');
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Blocked'), findsNothing);
    // A group that still has a row keeps its heading.
    expect(find.text('How you use MixSay'), findsOneWidget);
    expect(find.text('Support'), findsNothing);

    await tester.enterText(find.byType(TextField), 'language');
    await tester.pump();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);

    await tester.enterText(find.byType(TextField), 'mixsay');
    await tester.pump();
    expect(find.text('About MixSay'), findsOneWidget);
    expect(find.text('Blocked'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No setting matches that'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Blocked'), findsOneWidget);
  });

  testWidgets('the language row shows the choice and changes it', (
    tester,
  ) async {
    _useTallViewport(tester);
    final (container, _) = await _pump(tester, const Locale('en'));

    // Nothing picked yet, so both switches read the system default.
    expect(find.text('Follow system'), findsNWidgets(2));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arabic'));
    await tester.pumpAndSettle();
    expect(container.read(localeControllerProvider), const Locale('ar'));
    expect(find.text('العربية'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'ar');
  });

  testWidgets('the appearance row writes the theme mode', (tester) async {
    _useTallViewport(tester);
    final (container, _) = await _pump(tester, const Locale('en'));

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode'), 'light');
  });

  testWidgets('a row with a screen of its own opens it', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('reached/settings/notifications'), findsOneWidget);
    expect(find.text('Settings and activity'), findsNothing);
  });

  testWidgets('a row without a screen says coming soon', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsOneWidget);
    expect(
      find.text('This part is still being built. Nothing has changed.'),
      findsOneWidget,
    );
  });

  testWidgets('signing out asks first', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(
      find.text('You will be signed out of this device. Are you sure?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // Still on settings: nothing was signed out.
    expect(find.text('Settings and activity'), findsOneWidget);
  });

  testWidgets('Arabic mirrors the rows and their chevrons', (tester) async {
    _useTallViewport(tester);
    await _pump(tester, const Locale('ar'));

    expect(
      Directionality.of(tester.element(find.byType(SettingsScreen))),
      TextDirection.rtl,
    );
    expect(find.text('الإعدادات والنشاط'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsWidgets);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    // The heading starts at the Arabic edge.
    expect(
      tester.getRect(find.text('حسابك')).right,
      closeTo(390 - AppSpacing.xl, 0.6),
    );
  });

  testWidgets('the list scrolls instead of clipping at a big text scale', (
    tester,
  ) async {
    _useTallViewport(tester, height: 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, const Locale('ar'));

    // The last heading sits under the fold at this size: it has to be
    // reachable by scrolling, not cut off.
    await tester.dragUntilVisible(
      find.text('الدعم'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('الدعم')).bottom, lessThan(700));
    expect(tester.takeException(), isNull);
  });
}
