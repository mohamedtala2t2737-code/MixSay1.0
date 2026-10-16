import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/features/profile/data/follow_repository.dart';
import 'package:social_chat/features/profile/presentation/follow_graph_screen.dart';
import 'package:social_chat/features/profile/presentation/follow_providers.dart';

const _people = [
  FollowedUser(id: 'u1', username: 'cairo.coffee', fullName: 'Cairo Coffee'),
  FollowedUser(id: 'u2', username: 'no.name', fullName: ''),
];

Widget _harness(
  Locale locale, {
  required bool followers,
  required List<FollowedUser> people,
  Set<String> alreadyFollowing = const {},
}) {
  return ProviderScope(
    overrides: [
      followersListProvider.overrideWith((ref, userId) async => people),
      followingListProvider.overrideWith((ref, userId) async => people),
      isFollowingProvider.overrideWith(
        (ref, targetId) async => alreadyFollowing.contains(targetId),
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
      home: FollowGraphScreen(userId: 'user-me', followers: followers),
    ),
  );
}

void main() {
  testWidgets('the follower list names each person and offers a follow back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const Locale('en'), followers: true, people: _people),
    );
    await tester.pumpAndSettle();

    expect(find.text('Followers'), findsOneWidget);
    expect(find.text('Cairo Coffee'), findsOneWidget);
    // A profile with no display name falls back to the handle.
    expect(find.text('no.name'), findsNWidgets(2));
    expect(find.text('Follow'), findsNWidgets(2));
  });

  testWidgets('a person already followed reads as followed', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        followers: false,
        people: _people,
        alreadyFollowing: const {'u1'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Following'), findsNWidgets(2));
    expect(find.text('Follow'), findsOneWidget);
  });

  testWidgets('an empty graph says so in the language of the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const Locale('ar'), followers: false, people: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('أتابع'), findsOneWidget);
    expect(find.text('انت مش بتتابع حد لسه'), findsOneWidget);
  });
}
