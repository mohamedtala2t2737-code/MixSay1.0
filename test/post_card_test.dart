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
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/home/presentation/widgets/post_carousel.dart';
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

/// A carousel post: several urls, the first mirrored into `mediaUrl` the way
/// the repository writes it.
FeedPost _withSlides(List<String> urls, {bool isLiked = false}) => FeedPost(
  id: 'post-carousel',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: 'Slow moments in Cairo',
  mediaUrl: urls.first,
  mediaUrls: urls,
  likesCount: 249,
  commentsCount: 3,
  createdAt: null,
  artworkVariant: 0,
  isLiked: isLiked,
  mediaType: 'image',
);

/// A post nobody has reacted to yet: the card still has to show both counters.
const _quietPost = FeedPost(
  id: 'post-quiet',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: 'Slow moments in Cairo',
  likesCount: 0,
  commentsCount: 0,
  createdAt: null,
  artworkVariant: 0,
  isLiked: false,
  mediaType: 'none',
);

FeedPost _withCaption(String caption) => FeedPost(
  id: 'post-long',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: caption,
  likesCount: 1,
  commentsCount: 0,
  createdAt: null,
  artworkVariant: 0,
  isLiked: false,
  mediaType: 'none',
);

/// Long enough that three lines cannot hold it at any of the tested widths.
const _longCaption =
    'Slow moments in Cairo, written down while the tram was still '
    'crossing the bridge: the same six streets, the same bread shop on the '
    'corner, and the same driver who always waits one second longer than he '
    'needs to before he rings the bell.';

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
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('volume$playerId:$volume');
  }

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

/// The most recent volume the player wrapper asked the platform for.
String _lastVolume() =>
    _video.calls.lastWhere((call) => call.startsWith('volume'));

/// The default 800x600 test surface is wider than it is tall, so a square photo
/// plus the rest of the card does not fit on it: the media tests use a phone.
void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Stands in for the like write so the double-tap path can be observed without
/// Firebase: it records the posts it was asked to like and can fail on request.
class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository({this.likeError, this.holdLike = false});

  /// Thrown by `toggleLike` after [likeGate] completes, which is how a test
  /// watches the card while the write is still in flight.
  final Object? likeError;
  final bool holdLike;

  final List<String> liked = <String>[];
  final Completer<void> likeGate = Completer<void>();

  @override
  Future<void> toggleLike({required FeedPost post}) async {
    liked.add(post.id);
    if (holdLike || likeError != null) await likeGate.future;
    if (likeError != null) throw likeError!;
  }

  @override
  Stream<List<FeedComment>> watchComments(String postId) =>
      Stream.value(const <FeedComment>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Widget _harness(
  Locale locale, {
  FeedPost post = _post,
  String? asUser,
  FeedRepository? feed,
}) => ProviderScope(
  overrides: [
    if (asUser != null) currentUserIdProvider.overrideWithValue(asUser),
    if (feed != null) feedRepositoryProvider.overrideWith((ref) => feed),
  ],
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
    expect(find.text('View all 3 comments'), findsOneWidget);
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
    expect(find.text('عرض كل التعليقات (٣)'), findsOneWidget);

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

    // Initialising the player leaves it paused, not playing. The volume call
    // is the player wrapper applying its own default, not the mute button.
    expect(_video.calls, <String>['create0', 'volume0:1.0', 'pause0']);

    await tester.tap(find.byType(PostVideo));
    // The player recognises a single tap only once the double-tap window has
    // closed, so the play call lands after that timeout rather than instantly.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The player is created, idles paused, then the tap starts playback.
    expect(_video.calls.last, 'play0');

    await tester.tap(find.byType(PostVideo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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

  Color dimDot(ColorScheme scheme) =>
      scheme.onSurfaceVariant.withValues(alpha: 0.35);

  /// The carousel's page indicator as one flag per dot: filled or dimmed. Only
  /// the indicator's own two colours count, so the avatar's round Container
  /// beside it is not mistaken for a dot.
  List<bool> indicator(WidgetTester tester) {
    final scheme = Theme.of(tester.element(find.byType(PostCarousel)))
        .colorScheme;
    return tester
        .widgetList<Container>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        )
        .map((box) => (box.decoration! as BoxDecoration).color)
        .where((color) => color == scheme.onSurface || color == dimDot(scheme))
        .map((color) => color == scheme.onSurface)
        .toList();
  }

  testWidgets('several photos swipe with one dot per slide', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withSlides(<String>[
          'https://example.test/a.jpg',
          'https://example.test/b.jpg',
          'https://example.test/c.jpg',
        ]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PageView), findsOneWidget);
    expect(indicator(tester), <bool>[true, false, false]);

    await tester.fling(find.byType(PostCarousel), const Offset(-300, 0), 800);
    await tester.pumpAndSettle();
    expect(indicator(tester), <bool>[false, true, false]);

    await tester.fling(find.byType(PostCarousel), const Offset(300, 0), 800);
    await tester.pumpAndSettle();
    expect(indicator(tester), <bool>[true, false, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-photo post shows no indicator', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withSlides(<String>['https://example.test/a.jpg']),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PageView), findsNothing);
    expect(indicator(tester), isEmpty);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('double-tapping the photo likes the post once', (tester) async {
    _usePhone(tester);
    final feed = _FakeFeedRepository();
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withSlides(<String>['https://example.test/a.jpg']),
        feed: feed,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.favorite_rounded), findsNothing);

    await tester.tap(find.byType(PostCarousel));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(PostCarousel));
    await tester.pump();

    expect(feed.liked, <String>['post-carousel']);
    // The burst heart, plus the action row that already reads as liked because
    // the like is painted before the write answers.
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
    expect(find.byTooltip('Unlike'), findsOneWidget);
    expect(find.text('250 likes'), findsOneWidget);

    // The burst is a one-shot animation, not a permanent badge.
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('double-tapping a post that is already liked changes nothing', (
    tester,
  ) async {
    final feed = _FakeFeedRepository();
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withSlides(<String>[
          'https://example.test/a.jpg',
        ], isLiked: true),
        feed: feed,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(PostCarousel));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(PostCarousel));
    await tester.pump();

    expect(feed.liked, isEmpty);
    // Drain the burst and the gesture timers so the test ends clean.
    await tester.pumpAndSettle();
  });

  testWidgets('the mute button silences the clip and can undo it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        post: _withMedia('video', 'https://example.test/clip.mp4'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(_lastVolume(), 'volume0:0.0');
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Unmute'));
    await tester.pumpAndSettle();
    // The player already asked for full volume once while initialising, so the
    // newest call is the one that matters.
    expect(_lastVolume(), 'volume0:1.0');
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long caption folds to three lines and opens with see more', (
    tester,
  ) async {
    final caption = List.generate(
      20,
      (index) => 'line ${index + 1} of the long story behind this post',
    ).join(' ');

    await tester.pumpWidget(
      _harness(const Locale('en'), post: _withCaption(caption)),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(caption)).maxLines, 3);
    expect(find.text('See more'), findsOneWidget);
    expect(find.text('See less'), findsNothing);

    await tester.tap(find.text('See more'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(caption)).maxLines, isNull);
    expect(find.text('See less'), findsOneWidget);

    await tester.tap(find.text('See less'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(caption)).maxLines, 3);
  });

  testWidgets('a short caption gets no fold label', (tester) async {
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('See more'), findsNothing);
    expect(find.text('See less'), findsNothing);
  });

  testWidgets('a caption that only fits at a small font folds in Arabic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness(const Locale('ar'), post: _withCaption(_longCaption)),
    );
    await tester.pumpAndSettle();

    expect(find.text('اقرأ المزيد'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('اقرأ المزيد'));
    await tester.pumpAndSettle();

    expect(find.text('عرض أقل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three-dots menu reports any post and deletes only mine', (
    tester,
  ) async {
    Future<void> openMenu({required String viewerId}) async {
      await tester.pumpWidget(_harness(const Locale('en'), asUser: viewerId));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Post options'));
      await tester.pumpAndSettle();
    }

    await openMenu(viewerId: 'someone-else');

    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    // A link is only offered once AppLinks carries a real domain.
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Delete post'), findsNothing);

    await tester.tap(find.text('Report post'));
    await tester.pumpAndSettle();

    // The report sheet replaces the menu instead of stacking behind it.
    expect(find.text('Choose the reason that fits'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a post of mine keeps the delete row', (tester) async {
    await tester.pumpWidget(_harness(const Locale('en'), asUser: 'author-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();

    expect(find.text('Delete post'), findsOneWidget);
    expect(find.text('Report post'), findsOneWidget);
  });

  testWidgets('a like paints before the server answers', (tester) async {
    final feed = _FakeFeedRepository(holdLike: true);
    await tester.pumpWidget(_harness(const Locale('en'), feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Like'));
    await tester.pump();

    // The write is still open: the heart and the number moved anyway.
    expect(feed.liked, <String>['post-1']);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('250 likes'), findsOneWidget);

    feed.likeGate.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unlike'), findsOneWidget);
    expect(find.text('250 likes'), findsOneWidget);
  });

  testWidgets('a like the server refuses goes back', (tester) async {
    final feed = _FakeFeedRepository(
      likeError: Exception('firestore/permission-denied'),
    );
    await tester.pumpWidget(_harness(const Locale('en'), feed: feed));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Like'));
    await tester.pump();
    expect(find.text('250 likes'), findsOneWidget);

    feed.likeGate.complete();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.text('249 likes'), findsOneWidget);
    expect(find.textContaining('Could not complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an untouched post still shows both counters', (tester) async {
    await tester.pumpWidget(_harness(const Locale('en'), post: _quietPost));
    await tester.pumpAndSettle();

    expect(find.text('0 likes'), findsOneWidget);
    expect(find.text('No comments yet'), findsOneWidget);
  });

  testWidgets('view all comments opens the thread', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Locale('en'),
        asUser: 'user-me',
        feed: _FakeFeedRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View all 3 comments'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add a comment…'), findsOneWidget);
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
