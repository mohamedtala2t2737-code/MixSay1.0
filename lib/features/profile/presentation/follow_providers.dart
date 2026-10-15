import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/profile/data/follow_repository.dart';

final followRepositoryProvider = Provider<FollowRepository>(
  (ref) => FollowRepository(),
);

final followerCountProvider = FutureProvider.autoDispose
    .family<FollowCount, String>((ref, userId) {
      return ref.watch(followRepositoryProvider).followerCount(userId);
    });

final followingCountProvider = FutureProvider.autoDispose
    .family<FollowCount, String>((ref, userId) {
      return ref.watch(followRepositoryProvider).followingCount(userId);
    });

/// Whether the signed-in user follows [targetId].
final isFollowingProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  targetId,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(followRepositoryProvider).isFollowing(targetId);
});

final followersListProvider = FutureProvider.autoDispose
    .family<List<FollowedUser>, String>((ref, userId) {
      return ref.watch(followRepositoryProvider).followersOf(userId);
    });

final followingListProvider = FutureProvider.autoDispose
    .family<List<FollowedUser>, String>((ref, userId) {
      return ref.watch(followRepositoryProvider).followingOf(userId);
    });

/// Follows or unfollows [targetId] and refreshes every number that moved.
///
/// Returns null when the write was refused, so the caller can show its own
/// failure message without the repository knowing about widgets.
Future<bool?> toggleFollow(WidgetRef ref, String targetId) async {
  final repository = ref.read(followRepositoryProvider);
  final following = ref.read(isFollowingProvider(targetId)).value ?? false;
  try {
    await repository.setFollowing(targetId, following: !following);
  } catch (error, stackTrace) {
    debugPrint('Unable to update a MixSay follow: $error');
    debugPrintStack(stackTrace: stackTrace);
    return null;
  }
  ref
    ..invalidate(isFollowingProvider(targetId))
    ..invalidate(followerCountProvider(targetId));
  final me = ref.read(currentUserIdProvider);
  if (me != null) ref.invalidate(followingCountProvider(me));
  return !following;
}
