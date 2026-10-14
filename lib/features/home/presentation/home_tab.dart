import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/home/presentation/create_post_sheet.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';
import 'package:social_chat/features/home/presentation/widgets/stories_bar.dart';
import 'package:social_chat/features/stories/presentation/story_providers.dart';

/// Home tab: stories rail on top, then the post feed.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final posts = ref.watch(feedPostsProvider);
    final items = posts.value ?? const <FeedPost>[];

    Widget? status;
    if (posts.hasError) {
      debugPrint('Unable to load the MixSay feed: ${posts.error}');
      status = ErrorStateView(
        message: s.loadFailed,
        onRetry: () => ref.invalidate(feedPostsProvider),
      );
    } else if (posts.isLoading && items.isEmpty) {
      status = const LoadingView();
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeStoriesProvider);
        ref.invalidate(feedPostsProvider);
      },
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: StoriesBar()),
          if (status != null)
            SliverToBoxAdapter(
              child: SizedBox(
                // Scaled with the text size: a fixed 300/340 block clipped the
                // empty-feed button once the system font scale went up.
                height: scaler.scale(300),
                child: status,
              ),
            )
          else if (items.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: scaler.scale(340),
                child: EmptyStateView(
                  icon: Icons.auto_awesome_outlined,
                  title: s.feedEmptyTitle,
                  subtitle: s.feedEmptySubtitle,
                  actionLabel: s.createPost,
                  onAction: () => showCreatePostSheet(context),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => PostCard(post: items[index]),
            ),
        ],
      ),
    );
  }
}
