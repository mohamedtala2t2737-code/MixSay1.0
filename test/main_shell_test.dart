import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/home/presentation/main_shell.dart';
import 'package:social_chat/features/home/presentation/home_tab.dart';
import 'package:social_chat/features/notifications/data/notification_repository.dart';
import 'package:social_chat/features/notifications/presentation/notification_providers.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';
import 'package:social_chat/features/stories/presentation/story_providers.dart';

const _me = AppUser(
  id: 'user-me',
  username: 'mixsay.user',
  fullName: 'MixSay User',
);

Widget _harness(Locale locale) => ProviderScope(
  overrides: [
    currentUserIdProvider.overrideWithValue('user-me'),
    currentProfileProvider.overrideWith((ref) async => _me),
    feedPostsProvider.overrideWith((ref) => Stream.value(const <FeedPost>[])),
    authorPostsProvider.overrideWith(
      (ref, authorId) => Stream.value(const <FeedPost>[]),
    ),
    activeStoriesProvider.overrideWith(
      (ref) => Stream.value(const <StoryGroup>[]),
    ),
    notificationsProvider.overrideWith(
      (ref) => Stream.value(const <AppNotification>[]),
    ),
    conversationsProvider.overrideWith(
      (ref) => Stream.value(const <ChatConversationPreview>[]),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.dark,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: const MainShell(),
  ),
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _centerX(WidgetTester tester, Finder finder) =>
    tester.getCenter(finder).dx;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the English shell shows the wordmark, search and hamburger', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('MixSay'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(MainShell))),
      TextDirection.ltr,
    );
    expect(
      Theme.of(tester.element(find.byType(MainShell))).scaffoldBackgroundColor,
      AppColors.darkBackground,
    );
    expect(AppColors.darkBackground, const Color(0xFF121212));
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    final direction = locale.languageCode == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;

    testWidgets(
      'the home bar pins menu left and search right in ${locale.languageCode}',
      (tester) async {
        _usePhoneViewport(tester);
        await tester.pumpWidget(_harness(locale));
        await tester.pumpAndSettle();

        final menuX = _centerX(tester, find.byIcon(Icons.menu_rounded));
        final searchX = _centerX(tester, find.byIcon(Icons.search));
        final wordmarkX = _centerX(tester, find.text('MixSay'));

        // Physical sides, not start/end: an Arabic user must not get them
        // swapped, and the wordmark must not drift because the two icons have
        // different widths.
        expect(menuX, lessThan(60));
        expect(searchX, greaterThan(390 - 60));
        expect(wordmarkX, closeTo(195, 2));

        // Only the bar is pinned; the screen behind it still mirrors.
        expect(
          Directionality.of(tester.element(find.byType(MainShell))),
          direction,
        );
        expect(
          Directionality.of(tester.element(find.byIcon(Icons.search))),
          TextDirection.ltr,
        );
        expect(
          Directionality.of(tester.element(find.byType(HomeTab))),
          direction,
        );
      },
    );
  }

  testWidgets('the flat bar keeps the create item centred and level in LTR', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    expect(_centerX(tester, find.byTooltip('Create a post')), closeTo(195, 1));
    expect(
      _centerX(tester, find.byIcon(Icons.home_filled)),
      lessThan(_centerX(tester, find.byIcon(Icons.mail_outline_rounded))),
    );
    expect(
      _centerX(tester, find.byIcon(Icons.mail_outline_rounded)),
      lessThan(_centerX(tester, find.byIcon(Icons.add_rounded))),
    );
    expect(
      _centerX(tester, find.byIcon(Icons.add_rounded)),
      lessThan(_centerX(tester, find.byIcon(Icons.notifications_none_rounded))),
    );
    expect(
      _centerX(tester, find.byIcon(Icons.notifications_none_rounded)),
      lessThan(_centerX(tester, find.byIcon(Icons.account_circle_outlined))),
    );

    // Flat bar: the centre item sits on the same line as its neighbours, so
    // there is no raised button and no arch left over from the old design.
    final createY = tester.getCenter(find.byIcon(Icons.add_rounded)).dy;
    for (final icon in [
      Icons.home_filled,
      Icons.mail_outline_rounded,
      Icons.notifications_none_rounded,
      Icons.account_circle_outlined,
    ]) {
      expect(tester.getCenter(find.byIcon(icon)).dy, closeTo(createY, 1));
    }
  });

  testWidgets(
    'the centre item opens the composer and never takes the tab highlight',
    (tester) async {
      _usePhoneViewport(tester);
      await tester.pumpWidget(_harness(const Locale('en')));
      await tester.pumpAndSettle();

      Color iconColor(IconData icon) =>
          tester.widget<Icon>(find.byIcon(icon)).color!;
      final scheme = Theme.of(tester.element(find.byIcon(Icons.home_filled)))
          .colorScheme;

      // Home starts selected, so the create item must not be the primary colour
      // even though it now lives between the tabs.
      expect(iconColor(Icons.home_filled), scheme.primary);
      expect(iconColor(Icons.add_rounded), scheme.onSurfaceVariant);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Write a caption…'), findsOneWidget);
      expect(find.text('Post'), findsOneWidget);
      // The shell is still on Home behind the sheet.
      expect(find.text('MixSay'), findsOneWidget);
      expect(iconColor(Icons.add_rounded), scheme.onSurfaceVariant);
    },
  );

  testWidgets('the tab highlight follows the four indices after the reorder', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    Color iconColor(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;
    final scheme = Theme.of(tester.element(find.byIcon(Icons.home_filled)))
        .colorScheme;

    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(iconColor(Icons.account_circle_outlined), scheme.primary);
    expect(iconColor(Icons.home_filled), scheme.onSurfaceVariant);
    expect(find.text('My posts'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mail_outline_rounded));
    await tester.pumpAndSettle();
    expect(iconColor(Icons.mail_outline_rounded), scheme.primary);
    expect(iconColor(Icons.account_circle_outlined), scheme.onSurfaceVariant);

    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(iconColor(Icons.home_filled), scheme.primary);
    expect(find.text('MixSay'), findsOneWidget);
  });

  testWidgets('the same tab order mirrors to the right in Arabic', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_harness(const Locale('ar')));
    await tester.pumpAndSettle();

    expect(
      Directionality.of(tester.element(find.byType(MainShell))),
      TextDirection.rtl,
    );
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('حكايتك'), findsOneWidget);
    expect(_centerX(tester, find.byTooltip('منشور جديد')), closeTo(195, 1));
    expect(
      tester.getCenter(find.byIcon(Icons.add_rounded)).dy,
      closeTo(tester.getCenter(find.byIcon(Icons.home_filled)).dy, 1),
    );
    expect(
      _centerX(tester, find.byIcon(Icons.home_filled)),
      greaterThan(_centerX(tester, find.byIcon(Icons.mail_outline_rounded))),
    );
    expect(
      _centerX(tester, find.byIcon(Icons.notifications_none_rounded)),
      greaterThan(_centerX(tester, find.byIcon(Icons.account_circle_outlined))),
    );
  });

  testWidgets('tapping a tab swaps the AppBar title', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('My posts'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('My posts'), findsNothing);

    await tester.tap(find.byIcon(Icons.mail_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('MixSay'), findsNothing);

    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text('MixSay'), findsOneWidget);
  });

  testWidgets('every tab still lays out at a large system text scale', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_harness(const Locale('ar')));
    await tester.pumpAndSettle();

    // An overflow in any of these tabs throws during the pump, which fails the
    // test — this is where the previously hard-coded rail and bar heights bit.
    for (final icon in [
      Icons.account_circle_outlined,
      Icons.notifications_none_rounded,
      Icons.mail_outline_rounded,
      Icons.home_filled,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });
}
