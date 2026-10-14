import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => StoryRepository(),
);

/// Every author with a story younger than 24 hours, freshest first.
final activeStoriesProvider = StreamProvider.autoDispose<List<StoryGroup>>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream.error(StateError('Sign in to view stories'));
  }
  return ref.watch(storyRepositoryProvider).watchActiveStoryGroups();
});
