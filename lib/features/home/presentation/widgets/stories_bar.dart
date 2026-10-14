import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/utils/picked_image.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';
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

    if (groupsAsync.hasError) {
      // Without this the rail used to render as an empty row of nothing at all
      // whenever the read failed, which looked like "nobody posted".
      return SizedBox(
        height: 96,
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
      return const SizedBox(
        height: 96,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    final ordered = <StoryGroup>[...mine, ...others];

    return SizedBox(
      height: 96,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _StoryTile(
              name: s.yourStory,
              avatarUrl: profile?.avatarUrl,
              fallbackName: profile?.fullName ?? profile?.username ?? '',
              hasStory: mine.isNotEmpty,
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
            for (var index = 0; index < ordered.length; index++)
              _StoryTile(
                name: ordered[index].username,
                avatarUrl: ordered[index].avatarUrl,
                fallbackName: ordered[index].displayName,
                hasStory: true,
                showPlus: false,
                busy: false,
                onTap: () => _openViewer(ordered, index),
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
              borderRadius: BorderRadius.circular(4),
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
    required this.hasStory,
    required this.showPlus,
    required this.busy,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final String? avatarUrl;
  final String fallbackName;
  final bool hasStory;
  final bool showPlus;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _ringSize = 66.0;

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
            SizedBox(
              width: _ringSize,
              height: _ringSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: _ringSize,
                    height: _ringSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasStory
                          ? const SweepGradient(
                              colors: [
                                AppColors.brandBlue,
                                AppColors.brandYellow,
                                AppColors.brandPink,
                                AppColors.brandPurple,
                                AppColors.brandBlue,
                              ],
                            )
                          : null,
                      color: hasStory
                          ? null
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(hasStory ? 3 : 2),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surface,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: UserAvatar(
                            name: fallbackName,
                            url: avatarUrl,
                            radius: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: _ringSize,
                      height: _ringSize,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  if (showPlus)
                    PositionedDirectional(
                      bottom: 2,
                      end: 2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandBlue,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 12,
                          color: AppColors.onBrandGradient,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: hasStory
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
