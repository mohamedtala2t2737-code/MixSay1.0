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

  testWidgets('the curved bar keeps the create button centred in LTR', (
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
}
