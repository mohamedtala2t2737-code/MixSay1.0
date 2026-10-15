import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/profile/presentation/profile_tab_posts_provider.dart';

FeedPost _post(String id, String mediaType) => FeedPost(
  id: id,
  authorId: 'user-me',
  username: 'mixsay.user',
  fullName: 'MixSay User',
  caption: 'Caption $id',
  likesCount: 0,
  commentsCount: 0,
  createdAt: DateTime(2026, 10, 15),
  artworkVariant: 1,
  isLiked: false,
  mediaUrl: mediaType == 'none' ? null : 'https://example.com/$id.jpg',
  mediaType: mediaType,
);

List<FeedPost> _page(String prefix, int count, {String mediaType = 'image'}) => [
  for (var index = 0; index < count; index++) _post('$prefix-$index', mediaType),
];

/// A wall that hands back scripted pages instead of asking Firestore, so the
/// paging rules can be read without a backend.
class _ScriptedTab extends ProfileTabPostsController {
  _ScriptedTab(
    super.authorId,
    super.tab, {
    required this.pages,
    this.failOnFetch,
    this.gate,
    this.gateFrom = 0,
  });

  final List<List<FeedPost>> pages;

  /// The fetch number (0 is the first read) that throws instead of answering.
  final int? failOnFetch;

  /// When set, reads from [gateFrom] on wait for it: how an in-flight page is
  /// held open.
  final Completer<void>? gate;
  final int gateFrom;

  int fetches = 0;

  @override
  Future<FeedPostPage> fetchPage({DocumentSnapshot? after}) async {
    final number = fetches;
    fetches++;
    if (gate != null && number >= gateFrom) await gate!.future;
    if (failOnFetch == number) throw StateError('page unavailable');
    final posts = pages[number < pages.length ? number : pages.length - 1];
    return FeedPostPage(
      posts: posts,
      hasMore: number + 1 < pages.length,
      // A fake has no real document to point at. The wall keeps the cursor it
      // already had, and that is what the next read is asked for.
      cursor: null,
    );
  }
}

void main() {
  const key = ('user-me', ProfilePostTab.images);

  ProviderContainer scripted({
    required List<List<FeedPost>> pages,
    int? failOnFetch,
    Completer<void>? gate,
    int gateFrom = 0,
  }) {
    final container = ProviderContainer(
      overrides: [
        profileTabPostsProvider.overrideWith2(
          (arg) => _ScriptedTab(
            arg.$1,
            arg.$2,
            pages: pages,
            failOnFetch: failOnFetch,
            gate: gate,
            gateFrom: gateFrom,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  _ScriptedTab wall(ProviderContainer container) =>
      container.read(profileTabPostsProvider(key).notifier) as _ScriptedTab;

  test('every tab names exactly one stored media type', () {
    expect(ProfilePostTab.images.mediaType, 'image');
    expect(ProfilePostTab.videos.mediaType, 'video');
    expect(ProfilePostTab.text.mediaType, 'none');
  });

  test('the first wall is one page and knows more is waiting', () async {
    final container = scripted(
      pages: [_page('a', 30), _page('b', 4)],
    );
    final first = await container.read(profileTabPostsProvider(key).future);

    expect(first.posts, hasLength(30));
    expect(first.hasMore, isTrue);
    expect(first.isLoadingMore, isFalse);
  });

  test('a short first page asks for nothing more', () async {
    final container = scripted(pages: [_page('a', 7)]);
    final first = await container.read(profileTabPostsProvider(key).future);

    expect(first.hasMore, isFalse);
    await wall(container).loadMore();
    expect(container.read(profileTabPostsProvider(key)).value!.posts, hasLength(7));
  });

  test('showing more appends the next page, then stops', () async {
    final container = scripted(
      pages: [_page('a', 30), _page('b', 4)],
    );
    final notifier = wall(container);
    await container.read(profileTabPostsProvider(key).future);

    await notifier.loadMore();
    expect(notifier.fetches, 2);
    final loaded = container.read(profileTabPostsProvider(key)).value!;
    expect(loaded.posts, hasLength(34));
    expect(loaded.hasMore, isFalse);

    await notifier.loadMore();
    expect(notifier.fetches, 2, reason: 'a finished wall reads nothing');
  });

  test('a failed page keeps the wall on screen and offers a retry', () async {
    final container = scripted(
      pages: [_page('a', 30), _page('b', 4)],
      failOnFetch: 1,
    );
    final notifier = wall(container);
    await container.read(profileTabPostsProvider(key).future);

    await notifier.loadMore();

    final failed = container.read(profileTabPostsProvider(key)).value!;
    expect(failed.posts, hasLength(30));
    expect(failed.hasMore, isTrue, reason: 'the retry has to stay reachable');
    expect(failed.moreError, isNotNull);
    expect(failed.isLoadingMore, isFalse);
  });

  test('a second tap while a page is in flight asks for nothing', () async {
    final gate = Completer<void>();
    final container = scripted(
      pages: [_page('a', 30), _page('b', 4)],
      gate: gate,
      gateFrom: 1,
    );
    final notifier = wall(container);
    await container.read(profileTabPostsProvider(key).future);

    final inFlight = notifier.loadMore();
    await notifier.loadMore();
    expect(container.read(profileTabPostsProvider(key)).value!.isLoadingMore, isTrue);
    expect(notifier.fetches, 2, reason: 'the held page is not started twice');

    gate.complete();
    await inFlight;
    expect(container.read(profileTabPostsProvider(key)).value!.posts, hasLength(34));
  });

  test('the first read failing is the tab error state', () async {
    final container = scripted(pages: [_page('a', 30)], failOnFetch: 0);

    await expectLater(
      container.read(profileTabPostsProvider(key).future),
      throwsStateError,
    );
    expect(container.read(profileTabPostsProvider(key)).hasError, isTrue);
  });
}
