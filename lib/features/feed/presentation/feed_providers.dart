import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => FeedRepository(),
);

final feedPostsProvider = StreamProvider.autoDispose<List<FeedPost>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream.error(StateError('Sign in to view the MixSay feed'));
  }
  return ref.watch(feedRepositoryProvider).watchPosts();
});

final authorPostsProvider = StreamProvider.autoDispose
    .family<List<FeedPost>, String>((ref, authorId) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        return Stream.error(StateError('Sign in to view the MixSay feed'));
      }
      return ref.watch(feedRepositoryProvider).watchPostsByAuthor(authorId);
    });

final feedCommentsProvider = StreamProvider.autoDispose
    .family<List<FeedComment>, String>((ref, postId) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        return Stream.error(StateError('Sign in to view post comments'));
      }
      return ref.watch(feedRepositoryProvider).watchComments(postId);
    });
