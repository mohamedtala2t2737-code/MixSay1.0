import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_post_grid.dart';

/// The posts saved on this device.
///
/// Saves are local (see SavedPostsController), and the wall can only show what
/// the feed page returned, so a save older than the feed window is not listed.
class SavedPostsScreen extends ConsumerWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final saved = ref.watch(savedPostsProvider);
    final feed = ref.watch(feedPostsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.savedItem)),
      body: feed.when(
        loading: () => const LoadingView(),
        error: (error, stackTrace) {
          debugPrint('Unable to load saved posts: $error');
          return ErrorStateView(
            message: s.loadFailed,
            onRetry: () => ref.invalidate(feedPostsProvider),
          );
        },
        data: (posts) {
          final items = posts
              .where((post) => saved.contains(post.id))
              .toList(growable: false);
          return ProfilePostGrid(
            posts: items,
            empty: EmptyStateView(
              icon: Icons.bookmark_outline,
              title: s.noSavedPosts,
            ),
          );
        },
      ),
    );
  }
}
