import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/profile/data/follow_repository.dart';
import 'package:social_chat/features/profile/presentation/follow_providers.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_action_button.dart';

/// Either side of the follow graph, newest first, with the button that ends or
/// starts each row's follow.
class FollowGraphScreen extends ConsumerWidget {
  const FollowGraphScreen({
    super.key,
    required this.userId,
    required this.followers,
  });

  final String userId;

  /// True for the people who follow [userId], false for the people they follow.
  final bool followers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final rows = ref.watch(
      followers ? followersListProvider(userId) : followingListProvider(userId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(followers ? s.followersTitle : s.followingTitle),
      ),
      body: rows.when(
        loading: () => const LoadingView(),
        error: (error, stackTrace) {
          debugPrint('Unable to load a MixSay follow list: $error');
          return ErrorStateView(
            message: s.loadFailed,
            onRetry: () => ref.invalidate(
              followers
                  ? followersListProvider(userId)
                  : followingListProvider(userId),
            ),
          );
        },
        data: (people) {
          if (people.isEmpty) {
            return EmptyStateView(
              icon: followers
                  ? Icons.group_outlined
                  : Icons.person_add_outlined,
              title: followers ? s.noFollowers : s.noFollowing,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            itemCount: people.length,
            itemBuilder: (context, index) => _FollowRow(
              person: people[index],
              onChanged: () => ref.invalidate(
                followers
                    ? followersListProvider(userId)
                    : followingListProvider(userId),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FollowRow extends ConsumerWidget {
  const _FollowRow({required this.person, required this.onChanged});

  final FollowedUser person;

  /// Refreshes the list this row sits in, which drops an unfollowed person out
  /// of it.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final following = ref.watch(isFollowingProvider(person.id)).value ?? false;

    return AppListTile(
      leading: UserAvatar(name: person.displayName, url: person.avatarUrl),
      title: person.displayName,
      subtitle: person.username,
      trailing: ProfileActionButton(
        label: following ? s.followingButton : s.follow,
        filled: !following,
        onPressed: () async {
          final result = await toggleFollow(ref, person.id);
          if (!context.mounted) return;
          if (result == null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
            return;
          }
          onChanged();
        },
      ),
    );
  }
}
