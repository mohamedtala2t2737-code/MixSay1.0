import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart' show VideoPlayer;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';
import 'package:social_chat/features/home/presentation/widgets/post_video.dart';

const _post = FeedPost(
  id: 'post-1',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: 'Slow moments in Cairo',
  likesCount: 249,
  commentsCount: 3,
  createdAt: null,
  artworkVariant: 0,
  isLiked: false,
  mediaType: 'none',
);

FeedPost _withMedia(String mediaType, String url) => FeedPost(
  id: 'post-media',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: 'Slow moments in Cairo',
  mediaUrl: url,
  likesCount: 249,
  commentsCount: 3,
  createdAt: null,
  artworkVariant: 0,
  isLiked: false,
  mediaType: mediaType,
);

/// Stands in for the native player so the card's video branch can be tested
/// without a device: it reports a 30 second 640x360 clip and remembers whether
/// the widget asked it to play.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams =
      <int, StreamController<VideoEvent>>{};
  final List<String> calls = <String>[];
  int _nextId = 0;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextId++;
    calls.add('create$playerId');
    _streams[playerId] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(640, 360),
        ),
      );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    playCalls++;
    calls.add('play$playerId');
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
    calls.add('pause$playerId');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 6);

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Color(0xFF123456));
}

late _FakeVideoPlatform _video;

Widget _harness(Locale locale, {FeedPost post = _post}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(child: PostCard(post: post)),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _video = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = _video;
  });

  testWidgets('the English card shows the author, counters and actions', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('layla.hassan'), findsOneWidget);
    expect(find.text('Slow moments in Cairo'), findsOneWidget);
    expect(find.text('249 likes'), findsOneWidget);
    expect(find.text('3 comments'), findsOneWidget);
    for (final tooltip in ['Like', 'Comments', 'Share', 'Save']) {
      expect(find.byTooltip(tooltip), findsWidgets);
    }
  });

  testWidgets('saving a post is remembered in Arabic locale too', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('٢٤٩ إعجاب'), findsOneWidget);
    expect(find.text('٣ تعليق'), findsOneWidget);

    await tester.tap(find.byTooltip('حفظ'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('إلغاء الحفظ'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('saved_post_ids'), contains('post-1'));
  });

  void expectTopToBottomOrder(
    WidgetTester tester, {
    required String likeLabel,
  }) {
    final header = tester.getBottomLeft(find.byType(UserAvatar)).dy;
    final text = tester.getTopLeft(find.text('Slow moments in Cairo')).dy;
    final media = tester.getTopLeft(find.byType(PostVideo)).dy;
    final actions = tester.getTopLeft(find.byTooltip(likeLabel)).dy;
    final counters = tester
        .getTopLeft(find.text(likeLabel == 'Like' ? '249 likes' : '٢٤٩ إعجاب'))
        .dy;

    expect(header, lessThan(text));
    expect(text, lessThan(media));
    expect(media, lessThan(actions));
    expect(actions, lessThan(counters));
  }

  testWidgets('a video clip plays in the card instead of a static icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withMedia('video', 'https://example.test/clip.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);

    // Initialising the player leaves it paused, not playing.
    expect(_video.calls, <String>['create0', 'pause0']);

    await tester.tap(find.byType(PostVideo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // The player is created, idles paused, then the tap starts playback.
    expect(_video.calls, <String>['create0', 'pause0', 'play0']);

    await tester.tap(find.byType(PostVideo));
    await tester.pumpAndSettle();
    expect(_video.calls.last, 'pause0');
  });

  testWidgets('the card stacks header, text, media, actions, counters', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withMedia('video', 'https://example.test/clip.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    expectTopToBottomOrder(tester, likeLabel: 'Like');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same order holds in Arabic at a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness(
        const Locale('ar'),
        post: _withMedia('video', 'https://example.test/clip.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    expectTopToBottomOrder(tester, likeLabel: 'إعجاب');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image post renders the cached image in the media slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withMedia('image', 'https://example.test/photo.jpg'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final text = tester.getTopLeft(find.text('Slow moments in Cairo')).dy;
    final media = tester.getTopLeft(find.byType(CachedNetworkImage)).dy;
    final actions = tester.getTopLeft(find.byTooltip('Like')).dy;
    expect(text, lessThan(media));
    expect(media, lessThan(actions));
  });

  test('saved posts restore from preferences', () async {
    SharedPreferences.setMockInitialValues({
      'saved_post_ids': ['post-9', 'post-1'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(savedPostsProvider.notifier).restore();
    expect(container.read(savedPostsProvider), {'post-9', 'post-1'});
  });
}
