import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/profile/data/follow_repository.dart';
import 'package:social_chat/features/profile/presentation/follow_providers.dart';
import 'package:social_chat/features/profile/presentation/profile_screen.dart';

const _me = AppUser(
  id: 'user-me',
  username: 'mixsay.user',
  fullName: 'MixSay User',
  bio: 'Brews coffee and posts pictures of it.',
);

FeedPost _post(String id, {String mediaType = 'none', bool media = false}) =>
    FeedPost(
      id: id,
      authorId: _me.id,
      username: _me.username,
      fullName: _me.fullName,
      caption: 'Caption $id',
      likesCount: 0,
      commentsCount: 0,
      createdAt: DateTime(2026, 10, 15),
      artworkVariant: 1,
      isLiked: false,
      mediaUrl: media ? 'https://example.com/$id.jpg' : null,
      mediaType: mediaType,
    );

/// Pumps the profile over a router whose only job is to report where the screen
/// navigated, so a test can tell a real push from a button that does nothing.
Future<GoRouter> _pump(
  WidgetTester tester,
  Locale locale, {
  List<FeedPost> posts = const [],
  FollowCount followers = const FollowCount(0),
  FollowCount following = const FollowCount(0),
}) async {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      for (final path in ['/settings', '/followers', '/following'])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(
            body: Center(
              child: Text('$path:${state.uri.queryParameters['userId']}'),
            ),
          ),
        ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_me.id),
        currentProfileProvider.overrideWith((ref) async => _me),
        authorPostsProvider.overrideWith((ref, authorId) => Stream.value(posts)),
        followerCountProvider.overrideWith((ref, userId) async => followers),
        followingCountProvider.overrideWith((ref, userId) async => following),
      ],
      child: MaterialApp.router(
        locale: locale,
        routerConfig: router,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the header reads the signed-in account and its real numbers', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      posts: [_post('1'), _post('2'), _post('3'), _post('4')],
      followers: const FollowCount(7),
      following: const FollowCount(3),
    );

    expect(find.text('mixsay.user'), findsOneWidget);
    expect(find.text('MixSay User'), findsOneWidget);
    expect(find.text(_me.bio!), findsOneWidget);
    expect(find.text('posts'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('followers'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('following'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // The old tab layout is gone: no list heading, no sign-out button here.
    expect(find.text('My posts'), findsNothing);
    expect(find.text('Log out'), findsNothing);
  });

  testWidgets('a follower count that hit the read limit says so', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      followers: const FollowCount(200, capped: true),
    );

    expect(find.text('200+'), findsOneWidget);
  });

  testWidgets('the wall is three square columns with no gaps', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      posts: [
        _post('1', media: true),
        _post('2', media: true),
        _post('3', media: true),
      ],
    );

    expect(find.byType(CachedNetworkImage), findsNWidgets(3));
    final first = tester.getRect(find.byType(CachedNetworkImage).first);
    expect(first.width, closeTo(390 / 3, 0.5));
    expect(first.height, closeTo(first.width, 0.5));
    expect(first.left, 0);
  });

  testWidgets('a text post shows its caption in the tile', (tester) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'), posts: [_post('only')]);

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Caption only'), findsOneWidget);
  });

  testWidgets('the video tab keeps only the clips', (tester) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'), posts: [
      _post('photo', media: true),
      _post('clip', media: true, mediaType: 'video'),
    ]);

    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.ondemand_video_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
  });

  testWidgets('the repost and tagged tabs own their empty state', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'), posts: [_post('1', media: true)]);

    await tester.tap(find.byIcon(Icons.autorenew));
    await tester.pumpAndSettle();
    expect(find.text('Nothing reposted yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.local_offer_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Nothing tagged you in yet'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('an account with no posts points at the composer', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'));

    expect(find.text('You have not posted yet'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));

    await tester.tap(find.text('Create a post'));
    await tester.pumpAndSettle();
    expect(find.text('Write a caption…'), findsOneWidget);
  });

  testWidgets('the top bar opens the composer and then the settings', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Write a caption…'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('/settings:null'), findsOneWidget);
  });

  testWidgets('the follower numbers open this account’s lists', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final router = await _pump(
      tester,
      const Locale('en'),
      followers: const FollowCount(7),
      following: const FollowCount(3),
    );

    await tester.tap(find.text('followers'));
    await tester.pumpAndSettle();
    expect(find.text('/followers:user-me'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('following'));
    await tester.pumpAndSettle();
    expect(find.text('/following:user-me'), findsOneWidget);
  });

  testWidgets('a control with no screen behind it says so', (tester) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'), posts: [_post('1', media: true)]);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(
      find.text('This part is still being built. Nothing has changed.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Change photo'));
    await tester.pumpAndSettle();
    expect(
      find.text('This part is still being built. Nothing has changed.'),
      findsOneWidget,
    );
  });

  testWidgets('sharing copies the handle without inventing a link', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'));

    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map<Object?, Object?>)['text']
                as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.tap(find.text('Share profile'));
    await tester.pumpAndSettle();
    expect(copied, '@mixsay.user');
    expect(find.text('Username copied'), findsOneWidget);
  });

  testWidgets('Arabic mirrors the header but keeps the handle as typed', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('ar'),
      posts: [_post('1', media: true), _post('2', media: true)],
      followers: const FollowCount(7),
    );

    expect(
      Directionality.of(tester.element(find.byType(ProfileScreen))),
      TextDirection.rtl,
    );
    expect(find.text('متابع'), findsOneWidget);
    // A handle is Latin text with a dot in it: it must not be reversed.
    expect(
      Directionality.of(tester.element(find.text('mixsay.user'))),
      TextDirection.ltr,
    );
    // The wall starts at the Arabic edge, so the first tile sits on the right.
    expect(
      tester.getRect(find.byType(CachedNetworkImage).first).right,
      closeTo(390, 0.5),
    );
  });

  testWidgets('a large text scale does not clip the profile', (tester) async {
    _usePhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(
      tester,
      const Locale('ar'),
      posts: [_post('1', media: true), _post('2')],
      followers: const FollowCount(1234),
      following: const FollowCount(5678),
    );

    for (final icon in [
      Icons.ondemand_video_outlined,
      Icons.autorenew,
      Icons.local_offer_outlined,
      Icons.grid_view,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });
}
