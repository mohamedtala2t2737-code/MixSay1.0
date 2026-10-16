import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_radius.dart';
import 'package:social_chat/core/utils/picked_image.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';
import 'package:social_chat/features/stories/presentation/seen_stories_provider.dart';
import 'package:social_chat/features/stories/presentation/story_providers.dart';
import 'package:social_chat/features/home/presentation/widgets/story_viewer.dart';

/// Horizontally scrollable story rings: the signed-in user's circle first, with
/// a + badge, then every author with a story younger than 24 hours.
class StoriesBar extends ConsumerStatefulWidget {
  const StoriesBar({super.key});

  @override
  ConsumerState<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends ConsumerState<StoriesBar> {
  bool _uploading = false;

  Future<void> _addStory(ImageSource source) async {
    if (_uploading) return;
    final s = AppStrings.of(context);
    // Set before the picker opens: while it is on screen a second tap would
    // otherwise launch another sheet on top of the first.
    setState(() => _uploading = true);
    try {
      final picked = await pickAndCompressImage(source: source);
      if (picked == null) return;
      await ref
          .read(storyRepositoryProvider)
          .createStory(
            bytes: picked.bytes,
            contentType: picked.contentType,
            extension: picked.extension,
          );
      ref.invalidate(activeStoriesProvider);
    } catch (error, stackTrace) {
      debugPrint('Unable to publish a story: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openViewer(List<StoryGroup> groups, int index) {
    ref.read(seenStoriesProvider.notifier).markSeen(groups[index].authorId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StoryViewerPage(
          groups: groups,
          initialIndex: index,
          currentUserId: ref.read(currentUserIdProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final userId = ref.watch(currentUserIdProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final groupsAsync = ref.watch(activeStoriesProvider);
    final groups = groupsAsync.value ?? const <StoryGroup>[];
    // The ring plus the author name under it; the name has to keep growing
    // with the system text scale instead of being clipped by a fixed rail.
    final railHeight = MediaQuery.textScalerOf(context).scale(96);

    if (groupsAsync.hasError) {
      // Without this the rail used to render as an empty row of nothing at all
      // whenever the read failed, which looked like "nobody posted".
      return SizedBox(
        height: railHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.loadFailed,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(activeStoriesProvider),
                  child: Text(s.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (groupsAsync.isLoading) {
      return SizedBox(
        height: railHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _StorySkeletonTile(),
              _StorySkeletonTile(),
              _StorySkeletonTile(),
            ],
          ),
        ),
      );
    }

    final mine = groups.where((group) => group.authorId == userId).toList();
    final others = groups.where((group) => group.authorId != userId).toList();
    // The viewer swipes through one flat list, own stories first.
    final ordered = <StoryGroup>[...mine, ...others];
    final seen = ref.watch(seenStoriesProvider);

    return SizedBox(
      height: railHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _StoryTile(
              name: s.yourStory,
              avatarUrl: profile?.avatarUrl,
              fallbackName: profile?.fullName ?? profile?.username ?? '',
              story: mine.isNotEmpty ? AvatarStory.unseen : AvatarStory.seen,
              showPlus: true,
              busy: _uploading,
              onTap: () {
                if (mine.isNotEmpty) {
                  _openViewer(ordered, 0);
                } else {
                  _addStory(ImageSource.gallery);
                }
              },
              onLongPress: () => _addStory(ImageSource.camera),
            ),
            // Only the other authors: own stories are already the first tile,
            // and listing them again put the same face twice in the rail.
            for (var index = 0; index < others.length; index++)
              _StoryTile(
                name: others[index].username,
                avatarUrl: others[index].avatarUrl,
                fallbackName: others[index].displayName,
                story: seen.contains(others[index].authorId)
                    ? AvatarStory.seen
                    : AvatarStory.unseen,
                showPlus: false,
                busy: false,
                onTap: () => _openViewer(ordered, mine.length + index),
              ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder circles shown while the first story snapshot is still in
/// flight, so the rail does not look like an empty, featureless strip.
class _StorySkeletonTile extends StatelessWidget {
  const _StorySkeletonTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.chipBorder,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.name,
    required this.avatarUrl,
    required this.fallbackName,
    required this.story,
    required this.showPlus,
    required this.busy,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final String? avatarUrl;
  final String fallbackName;
  final AvatarStory story;
  final bool showPlus;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _faceRadius = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      child: InkWell(
        onTap: busy ? null : onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              name: fallbackName,
              url: avatarUrl,
              radius: _faceRadius,
              story: story,
              busy: busy,
              showPlus: showPlus,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: story == AvatarStory.seen
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
