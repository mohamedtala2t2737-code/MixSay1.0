import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';

/// The content tabs under the profile header. Each one is exactly one
/// `mediaType` value, which is what makes its wall a server-side query rather
/// than a filtered page.
enum ProfilePostTab {
  images('image'),
  videos('video'),
  text('none');

  const ProfilePostTab(this.mediaType);

  /// The value posts documents carry in `mediaType` for this tab.
  final String mediaType;
}

/// Which account's wall, and which tab of it.
typedef ProfileTabKey = (String authorId, ProfilePostTab tab);

/// What one tab is showing: the pages read so far and whether another is due.
class ProfileTabPosts {
  const ProfileTabPosts({
    required this.posts,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.moreError,
    this.cursor,
  });

  final List<FeedPost> posts;

  /// The last page came back full, so the next one is worth asking for.
  final bool hasMore;
  final bool isLoadingMore;

  /// Set when the next page failed while the posts already on screen stay put.
  final Object? moreError;

  /// Where the next page starts.
  final DocumentSnapshot? cursor;
}

/// One wall per (account, tab).
///
/// Deliberately not auto-dispose: a tab builds the first time it is opened and
/// its pages stay in the provider cache afterwards, so moving between the tabs
/// never refetches. Pull-to-refresh is the only thing that reloads it.
class ProfileTabPostsController extends AsyncNotifier<ProfileTabPosts> {
  ProfileTabPostsController(this.authorId, this.tab);

  final String authorId;
  final ProfilePostTab tab;

  /// The read this wall performs, split out so a test can hand back fake pages
  /// without a Firestore to talk to.
  Future<FeedPostPage> fetchPage({DocumentSnapshot? after}) =>
      ref.read(feedRepositoryProvider).fetchPostsByAuthorAndType(
        authorId: authorId,
        mediaType: tab.mediaType,
        after: after,
      );

  @override
  Future<ProfileTabPosts> build() async {
    final page = await fetchPage();
    return ProfileTabPosts(
      posts: page.posts,
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
  }

  /// Appends the next page. The wall keeps what it already had if the read
  /// fails, so a bad network never blanks the posts a person is looking at.
  Future<void> loadMore() async {
    final loaded = state.value;
    if (loaded == null || !loaded.hasMore || loaded.isLoadingMore) return;

    state = AsyncData(
      ProfileTabPosts(
        posts: loaded.posts,
        hasMore: loaded.hasMore,
        isLoadingMore: true,
        cursor: loaded.cursor,
      ),
    );
    try {
      final page = await fetchPage(after: loaded.cursor);
      state = AsyncData(
        ProfileTabPosts(
          posts: [...loaded.posts, ...page.posts],
          hasMore: page.hasMore,
          cursor: page.cursor ?? loaded.cursor,
        ),
      );
    } catch (error) {
      debugPrint('Unable to load more profile posts: $error');
      state = AsyncData(
        ProfileTabPosts(
          posts: loaded.posts,
          hasMore: loaded.hasMore,
          moreError: error,
          cursor: loaded.cursor,
        ),
      );
    }
  }
}

final profileTabPostsProvider =
    AsyncNotifierProvider.family<
      ProfileTabPostsController,
      ProfileTabPosts,
      ProfileTabKey
    >((key) => ProfileTabPostsController(key.$1, key.$2));
