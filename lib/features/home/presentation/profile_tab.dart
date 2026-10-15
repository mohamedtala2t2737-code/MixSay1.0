import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/auth/presentation/sign_out_action.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/home/presentation/create_post_sheet.dart';
import 'package:social_chat/features/home/presentation/widgets/mixsay_bottom_bar.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final userId = ref.watch(currentUserIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final posts = userId == null
        ? const AsyncLoading<List<FeedPost>>()
        : ref.watch(authorPostsProvider(userId));
    final items = posts.value ?? const <FeedPost>[];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentProfileProvider);
        if (userId != null) ref.invalidate(authorPostsProvider(userId));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom clearance = the usual gap plus the transparent bar.
        padding: const EdgeInsets.only(bottom: 24 + MixSayBottomBar.barHeight),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                UserAvatar(
                  name: profile?.fullName ?? profile?.username ?? '',
                  url: profile?.avatarUrl,
                  radius: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.username == null
                            ? ''
                            : '@${profile!.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if ((profile?.fullName ?? '').isNotEmpty)
                        Text(
                          profile!.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if ((profile?.bio ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            profile!.bio!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => confirmAndSignOut(context, ref),
              icon: const Icon(Icons.logout),
              label: Text(s.logOut),
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.myPosts,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (posts.hasError)
            SizedBox(
              height: 260,
              child: ErrorStateView(
                message: s.loadFailed,
                onRetry: () => ref.invalidate(authorPostsProvider(userId!)),
              ),
            )
          else if (posts.isLoading && items.isEmpty)
            const SizedBox(height: 220, child: LoadingView())
          else if (items.isEmpty)
            SizedBox(
              height: 300,
              child: EmptyStateView(
                icon: Icons.photo_library_outlined,
                title: s.noPostsYet,
                actionLabel: s.createPost,
                onAction: () => showCreatePostSheet(context),
              ),
            )
          else
            for (final post in items) PostCard(post: post),
        ],
      ),
    );
  }
}
