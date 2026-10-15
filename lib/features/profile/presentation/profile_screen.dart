import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/theme/app_typography.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/post_detail_screen.dart';
import 'package:social_chat/features/home/presentation/create_post_sheet.dart';
import 'package:social_chat/features/home/presentation/widgets/mixsay_bottom_bar.dart';
import 'package:social_chat/features/profile/presentation/follow_providers.dart';
import 'package:social_chat/features/profile/presentation/profile_tab_posts_provider.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_action_button.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_post_grid.dart';
import 'package:social_chat/features/profile/presentation/widgets/profile_stats_row.dart';

/// The account screen: the reference layout of the profile header, with every
/// number and word read from the signed-in user's own data.
///
/// It paints its own top bar because the shell drops its AppBar on this tab,
/// and the bar here carries the account name rather than a screen title.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Each content tab is one `mediaType`, and its wall is read from the server
  /// already filtered, so a page of 30 is 30 tiles of that tab.
  static const _tabIcons = {
    ProfilePostTab.images: Icons.grid_view,
    ProfilePostTab.videos: Icons.play_circle_outline,
    ProfilePostTab.text: Icons.text_snippet_outlined,
  };
  static const _tabEmptyIcons = {
    ProfilePostTab.images: Icons.photo_library_outlined,
    ProfilePostTab.videos: Icons.play_circle_outline,
    ProfilePostTab.text: Icons.text_snippet_outlined,
  };

  ProfilePostTab _tab = ProfilePostTab.images;

  void _sayComingSoon(AppStrings s) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.comingSoonMessage)));
  }

  Future<void> _shareProfile(AppStrings s, String username) async {
    await Clipboard.setData(ClipboardData(text: '@$username'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.profileShared)));
  }

  void _openFollowGraph(String path, String userId) {
    context.push('$path?userId=$userId');
  }

  /// The gap under the header that an empty or failed list fills. It is a
  /// minimum rather than a fixed height, so a large system text scale never
  /// clips the message inside it.
  Widget _gap(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 260),
    child: child,
  );

  Widget _tabBody(
    AppStrings s,
    ProfileTabKey? key,
    AsyncValue<ProfileTabPosts> wall,
  ) {
    if (key == null) return _gap(const LoadingView());
    if (wall.hasError && !wall.hasValue) {
      return _gap(
        ErrorStateView(
          message: s.loadFailed,
          onRetry: () => ref.invalidate(profileTabPostsProvider(key)),
        ),
      );
    }
    if (wall.isLoading && !wall.hasValue) {
      return const SizedBox(height: 220, child: LoadingView());
    }

    final data = wall.value!;
    return Column(
      children: [
        ProfilePostGrid(
          posts: data.posts,
          tab: key.$2,
          onPostTap: (post) => openPostDetail(context, post),
          empty: _gap(
            EmptyStateView(
              icon: _tabEmptyIcons[key.$2]!,
              title: switch (key.$2) {
                ProfilePostTab.images => s.noImages,
                ProfilePostTab.videos => s.noVideos,
                ProfilePostTab.text => s.noTextPosts,
              },
              actionLabel: key.$2 == ProfilePostTab.videos
                  ? null
                  : s.createPost,
              onAction: key.$2 == ProfilePostTab.videos
                  ? null
                  : () => showCreatePostSheet(context),
            ),
          ),
        ),
        _loadMore(s, key, data),
      ],
    );
  }

  /// The next page of this tab, or why it has not arrived. The tiles already on
  /// screen stay put either way.
  Widget _loadMore(AppStrings s, ProfileTabKey key, ProfileTabPosts data) {
    if (!data.hasMore) return const SizedBox.shrink();
    if (data.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Column(
      children: [
        if (data.moreError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(s.loadFailed, textAlign: TextAlign.center),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: TextButton(
            onPressed: () =>
                ref.read(profileTabPostsProvider(key).notifier).loadMore(),
            child: Text(s.showMore),
          ),
        ),
      ],
    );
  }

  Widget _tabRow(AppStrings s, String username, Color divider) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: divider)),
        ),
        child: Row(
          children: [
            for (final tab in ProfilePostTab.values)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = tab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: _tab == tab
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Icon(
                      _tabIcons[tab],
                      semanticLabel: switch (tab) {
                        ProfilePostTab.images => s.imagesTab,
                        ProfilePostTab.videos => s.videosTab,
                        ProfilePostTab.text => s.textTab,
                      },
                      color: _tab == tab
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            // Sharing is an action, not a fourth wall: it never takes the
            // underline and never changes what the other tabs show.
            IconButton(
              tooltip: s.shareProfile,
              onPressed: username.isEmpty
                  ? null
                  : () => _shareProfile(s, username),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final userId = ref.watch(currentUserIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final posts = userId == null
        ? const AsyncLoading<List<FeedPost>>()
        : ref.watch(authorPostsProvider(userId));
    final items = posts.value ?? const <FeedPost>[];
    final tabKey = userId == null ? null : (userId, _tab);
    final wall = tabKey == null
        ? const AsyncLoading<ProfileTabPosts>()
        : ref.watch(profileTabPostsProvider(tabKey));
    final followerCount = userId == null
        ? null
        : ref.watch(followerCountProvider(userId)).value;
    final followingCount = userId == null
        ? null
        : ref.watch(followingCountProvider(userId)).value;
    final username = profile?.username ?? '';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ProfileTopBar(
              username: username,
              onCreate: () => showCreatePostSheet(context),
              onSwitchAccounts: () => _sayComingSoon(s),
              onSettings: () => context.push('/settings'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(currentProfileProvider);
                  if (userId != null) {
                    ref
                      ..invalidate(authorPostsProvider(userId))
                      ..invalidate(followerCountProvider(userId))
                      ..invalidate(followingCountProvider(userId));
                  }
                  if (tabKey != null) {
                    ref.invalidate(profileTabPostsProvider(tabKey));
                    // The spinner stays until the tab has read a page again. A
                    // failed read is the tab's own problem to show, so it is
                    // swallowed here rather than thrown at the gesture.
                    await ref
                        .read(profileTabPostsProvider(tabKey).future)
                        .catchError((Object _) => const ProfileTabPosts(
                          posts: [],
                        ));
                  }
                },
                child: ListView(
                  // The bottom bar is transparent, so the wall has to end above
                  // it for the last row of tiles to be reachable.
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.lg + MixSayBottomBar.barHeight,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _AvatarButton(
                            name: profile?.fullName ?? username,
                            url: profile?.avatarUrl,
                            onTap: () => _sayComingSoon(s),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(
                            child: ProfileStatsRow(
                              stats: [
                                ProfileStat(
                                  value: s.number(items.length),
                                  label: s.postsStat,
                                ),
                                ProfileStat(
                                  value: s.number(followerCount?.label ?? '0'),
                                  label: s.followersStat,
                                  onTap: userId == null
                                      ? null
                                      : () => _openFollowGraph(
                                          '/followers',
                                          userId,
                                        ),
                                ),
                                ProfileStat(
                                  value: s.number(followingCount?.label ?? '0'),
                                  label: s.followingStat,
                                  onTap: userId == null
                                      ? null
                                      : () => _openFollowGraph(
                                          '/following',
                                          userId,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((profile?.fullName ?? '').isNotEmpty)
                      _TextBlock(title: profile!.fullName, bio: profile.bio),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.md,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ProfileActionButton(
                              label: s.editProfile,
                              onPressed: () => _sayComingSoon(s),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ProfileActionButton(
                              label: s.shareProfile,
                              onPressed: username.isEmpty
                                  ? null
                                  : () => _shareProfile(s, username),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _tabRow(s, username, theme.dividerColor),
                    _tabBody(s, tabKey, wall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The account row across the top: create a post, the account name, and the
/// menu that opens settings.
class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.username,
    required this.onCreate,
    required this.onSwitchAccounts,
    required this.onSettings,
  });

  final String username;
  final VoidCallback onCreate;
  final VoidCallback onSwitchAccounts;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          IconButton(
            tooltip: s.createPost,
            icon: const Icon(Icons.add_rounded),
            onPressed: onCreate,
          ),
          Expanded(
            child: InkWell(
              onTap: onSwitchAccounts,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      // The account name is a handle: it keeps its own
                      // left-to-right order even inside Arabic text.
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.emphasis,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: s.settingsAndActivity,
            icon: const Icon(Icons.menu_rounded),
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// The big face with the small badge that offers a new photo.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.name,
    required this.url,
    required this.onTap,
  });

  final String name;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: s.changePhoto,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(name: name, url: url, radius: 44),
            PositionedDirectional(
              bottom: 2,
              end: 2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 14,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The name line and the bio under it. Both are plain [Text]s, so Arabic reads
/// right-to-left and English left-to-right without a switch anywhere.
class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, this.bio});

  final String title;
  final String? bio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if ((bio ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                bio!,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The flat grey action button is [ProfileActionButton]; the header and the
/// follow lists share it.
