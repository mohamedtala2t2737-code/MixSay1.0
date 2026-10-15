import 'dart:async';

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
import 'package:social_chat/features/feed/presentation/post_detail_screen.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';
import 'package:social_chat/features/profile/data/follow_repository.dart';
import 'package:social_chat/features/profile/presentation/follow_providers.dart';
import 'package:social_chat/features/profile/presentation/profile_screen.dart';
import 'package:social_chat/features/profile/presentation/profile_tab_posts_provider.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_post_grid.dart';

const _me = AppUser(
  id: 'user-me',
  username: 'mixsay.user',
  fullName: 'MixSay User',
  bio: 'Brews coffee and posts pictures of it.',
);

FeedPost _post(
  String id, {
  String mediaType = 'none',
  List<String> mediaUrls = const [],
  String? caption,
}) => FeedPost(
  id: id,
  authorId: _me.id,
  username: _me.username,
  fullName: _me.fullName,
  caption: caption ?? 'Caption $id',
  likesCount: 0,
  commentsCount: 0,
  createdAt: DateTime(2026, 10, 15),
  artworkVariant: 1,
  isLiked: false,
  mediaUrl: mediaUrls.isEmpty ? null : mediaUrls.first,
  mediaUrls: mediaUrls,
  mediaType: mediaType,
);

FeedPost _photo(String id, {int slides = 1}) =>
    _post(
      id,
      mediaType: 'image',
      mediaUrls: [
        for (var index = 0; index < slides; index++)
          'https://example.com/$id-$index.jpg',
      ],
    );

FeedPost _clip(String id) =>
    _post(id, mediaType: 'video', mediaUrls: ['https://example.com/$id.mp4']);

/// What each tab answers with, and how often it was asked.
class _Walls {
  _Walls({
    this.pages = const {},
    Set<ProfilePostTab> failing = const {},
    Set<ProfilePostTab> silent = const {},
  }) : failing = {...failing},
       silent = {...silent};

  final Map<ProfilePostTab, List<FeedPost>> pages;
  final Set<ProfilePostTab> failing;

  /// Tabs whose read never comes back, which is how the loading state is shown.
  final Set<ProfilePostTab> silent;

  final builds = <ProfilePostTab, int>{};

  int buildsOf(ProfilePostTab tab) => builds[tab] ?? 0;
}

class _FakeTab extends ProfileTabPostsController {
  _FakeTab(super.authorId, super.tab, this.walls);

  final _Walls walls;

  @override
  Future<ProfileTabPosts> build() async {
    walls.builds[tab] = (walls.builds[tab] ?? 0) + 1;
    if (walls.silent.contains(tab)) return Completer<ProfileTabPosts>().future;
    if (walls.failing.contains(tab)) throw StateError('offline');
    return ProfileTabPosts(posts: walls.pages[tab] ?? const []);
  }
}

/// Pumps the profile over a router whose only job is to report where the screen
/// navigated, so a test can tell a real push from a button that does nothing.
Future<GoRouter> _pump(
  WidgetTester tester,
  Locale locale, {
  List<FeedPost> posts = const [],
  _Walls? walls,
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
        profileTabPostsProvider.overrideWith2(
          (key) => _FakeTab(key.$1, key.$2, walls ?? _Walls()),
        ),
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

Future<void> _open(WidgetTester tester, ProfilePostTab tab) async {
  await tester.tap(find.byIcon(_tabIconOf(tab)));
  await tester.pumpAndSettle();
}

IconData _tabIconOf(ProfilePostTab tab) => switch (tab) {
  ProfilePostTab.images => Icons.grid_view,
  ProfilePostTab.videos => Icons.play_circle_outline,
  ProfilePostTab.text => Icons.text_snippet_outlined,
};

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
    expect(find.text('My posts'), findsNothing);
    expect(find.text('Log out'), findsNothing);
  });

  testWidgets('the posts counter counts the account, not the open tab', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      posts: [
        _photo('a'),
        _photo('b'),
        _post('c', mediaType: 'video', mediaUrls: ['https://example.com/c.mp4']),
        _post('d'),
        _post('e'),
      ],
      walls: _Walls(pages: {ProfilePostTab.images: [_photo('a'), _photo('b')]}),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));

    await _open(tester, ProfilePostTab.text);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('the wall is three square columns with no gaps', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(
        pages: {ProfilePostTab.images: [_photo('1'), _photo('2'), _photo('3')]},
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNWidgets(3));
    final first = tester.getRect(find.byType(CachedNetworkImage).first);
    expect(first.width, closeTo(390 / 3, 0.5));
    expect(first.height, closeTo(first.width, 0.5));
    expect(first.left, 0);
  });

  testWidgets('only a carousel gets the multiple badge', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(
        pages: {
          ProfilePostTab.images: [_photo('single'), _photo('many', slides: 3)],
        },
      ),
    );

    expect(find.byIcon(Icons.copy_all_rounded), findsOneWidget);
    // The badge sits at the reading end of the tile, which mirrors in Arabic.
    final tile = tester.getRect(find.byType(CachedNetworkImage).last);
    expect(tester.getRect(find.byIcon(Icons.copy_all_rounded)).right,
        closeTo(tile.right, 12));
  });

  testWidgets('the videos tab is a placeholder wall with play marks', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(
        pages: {
          ProfilePostTab.videos: [_clip('a'), _clip('b')],
        },
      ),
    );

    await _open(tester, ProfilePostTab.videos);

    // No stored thumbnail, and the clip itself is never downloaded for one.
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));
  });

  testWidgets('the text tab keeps the caption inside four lines', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final long = List.generate(30, (index) => 'word $index').join(' ');
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(
        pages: {ProfilePostTab.text: [_post('note', caption: long)]},
      ),
    );

    await _open(tester, ProfilePostTab.text);

    final tile = tester.widget<Text>(find.text(long));
    expect(tile.maxLines, 4);
    expect(tile.overflow, TextOverflow.ellipsis);
    // The tile is a 130pt square with 8pt of padding, so an over-long caption
    // must cut itself off inside it rather than push the wall open.
    final rect = tester.getRect(find.text(long));
    expect(rect.height, lessThan(115));
  });

  testWidgets('an empty tab names its own content', (tester) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'));

    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Create a post'), findsOneWidget);

    await _open(tester, ProfilePostTab.videos);
    expect(find.text('No videos yet'), findsOneWidget);

    await _open(tester, ProfilePostTab.text);
    expect(find.text('No text posts yet'), findsOneWidget);
  });

  testWidgets('an empty images tab still points at the composer', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('en'));

    await tester.tap(find.text('Create a post'));
    await tester.pumpAndSettle();
    expect(find.text('Write a caption…'), findsOneWidget);
  });

  testWidgets('a tab that has not answered is the only thing spinning', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(
        pages: {ProfilePostTab.images: [_photo('1')]},
        silent: {ProfilePostTab.videos},
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byIcon(_tabIconOf(ProfilePostTab.videos)));
    // One frame only: an indeterminate spinner never stops asking for the next,
    // so settling on it would wait forever.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ProfilePostGrid), findsNothing);
    expect(find.text('No videos yet'), findsNothing);
  });

  testWidgets('a failed tab says so and its retry loads it', (tester) async {
    _usePhoneViewport(tester);
    final walls = _Walls(
      failing: {ProfilePostTab.videos},
      pages: {ProfilePostTab.videos: [_clip('a')]},
    );
    await _pump(tester, const Locale('en'), walls: walls);

    await _open(tester, ProfilePostTab.videos);
    expect(find.text('Failed to load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    walls.failing.clear();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('switching tabs does not ask a cached tab again', (tester) async {
    _usePhoneViewport(tester);
    final walls = _Walls(
      pages: {
        ProfilePostTab.images: [_photo('1')],
        ProfilePostTab.text: [_post('note')],
      },
    );
    await _pump(tester, const Locale('en'), walls: walls);

    expect(walls.buildsOf(ProfilePostTab.images), 1);
    // A tab nobody opened has never been read at all.
    expect(walls.buildsOf(ProfilePostTab.videos), 0);

    await _open(tester, ProfilePostTab.text);
    expect(walls.buildsOf(ProfilePostTab.text), 1);

    await _open(tester, ProfilePostTab.images);
    expect(walls.buildsOf(ProfilePostTab.images), 1);
    expect(walls.buildsOf(ProfilePostTab.text), 1);
  });

  testWidgets('the share icon is a button, not a fourth tab', (tester) async {
    _usePhoneViewport(tester);
    final walls = _Walls(pages: {ProfilePostTab.images: [_photo('1')]});
    await _pump(tester, const Locale('en'), walls: walls);

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

    final imagesTiles = find.byType(CachedNetworkImage);
    final before = tester.getRect(find.byIcon(Icons.grid_view));

    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();

    expect(copied, '@mixsay.user');
    // The same tab is open, its wall is unchanged, and no tab was re-read.
    expect(imagesTiles, findsOneWidget);
    expect(tester.getRect(find.byIcon(Icons.grid_view)), before);
    expect(walls.builds, {ProfilePostTab.images: 1});

    // It behaves the same from another tab, and it still does not select one.
    await _open(tester, ProfilePostTab.text);
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(find.text('No text posts yet'), findsOneWidget);
    expect(walls.builds.keys, {ProfilePostTab.images, ProfilePostTab.text});
  });

  testWidgets('a tile opens the post itself', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(pages: {ProfilePostTab.images: [_photo('open-me')]}),
    );

    // The tile's own InkWell is the thing that answers: the image inside it
    // has no gesture surface of its own.
    await tester.tap(
      find.descendant(
        of: find.byType(ProfilePostGrid),
        matching: find.byType(InkWell),
      ).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(find.text('Caption open-me'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsNothing);
  });

  testWidgets('a text tile opens the same post screen', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('en'),
      walls: _Walls(pages: {ProfilePostTab.text: [_post('note', caption: 'Only words')]}),
    );

    await _open(tester, ProfilePostTab.text);
    await tester.tap(find.text('Only words'));
    await tester.pumpAndSettle();

    expect(find.byType(PostCard), findsOneWidget);
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
    await _pump(tester, const Locale('en'));

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

  testWidgets('Arabic mirrors the wall and the tab order', (tester) async {
    _usePhoneViewport(tester);
    await _pump(
      tester,
      const Locale('ar'),
      walls: _Walls(
        pages: {ProfilePostTab.images: [_photo('1'), _photo('2')]},
      ),
    );

    expect(
      Directionality.of(tester.element(find.byType(ProfileScreen))),
      TextDirection.rtl,
    );
    expect(find.text('متابع'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('mixsay.user'))),
      TextDirection.ltr,
    );
    // The wall starts at the Arabic edge, so the first tile sits on the right.
    expect(
      tester.getRect(find.byType(CachedNetworkImage).first).right,
      closeTo(390, 0.5),
    );
    // The tabs mirror too: Images, the one opened by default, is the rightmost.
    expect(
      tester.getRect(find.byIcon(Icons.grid_view)).right,
      greaterThan(tester.getRect(find.byIcon(Icons.text_snippet_outlined)).right),
    );
  });

  testWidgets('Arabic empty tabs read in Arabic', (tester) async {
    _usePhoneViewport(tester);
    await _pump(tester, const Locale('ar'));

    expect(find.text('مافيش صور لسه'), findsOneWidget);
    await _open(tester, ProfilePostTab.videos);
    expect(find.text('مافيش فيديوهات لسه'), findsOneWidget);
    await _open(tester, ProfilePostTab.text);
    expect(find.text('مافيش منشورات نصية لسه'), findsOneWidget);
  });

  testWidgets('a large text scale does not clip the profile', (tester) async {
    _usePhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(
      tester,
      const Locale('ar'),
      walls: _Walls(
        pages: {
          ProfilePostTab.images: [_photo('1'), _photo('2')],
          ProfilePostTab.text: [_post('note', caption: 'كلام طويل')],
        },
      ),
      followers: const FollowCount(1234),
      following: const FollowCount(5678),
    );

    for (final tab in ProfilePostTab.values) {
      await _open(tester, tab);
    }
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
