import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/profile/presentation/profile_tab_posts_provider.dart';

/// The profile wall: three square columns, no gaps, the shape of the reference
/// design.
///
/// [tab] decides what a tile is allowed to paint, so a video tile never reaches
/// for the network: there is no stored thumbnail, and downloading a clip just to
/// show a still is the slowest possible way to draw a grey box.
///
/// With no [tab] the wall keeps the older behaviour of painting whatever the
/// post carries, which is what the saved-posts list shows.
class ProfilePostGrid extends StatelessWidget {
  const ProfilePostGrid({
    super.key,
    required this.posts,
    required this.empty,
    this.tab,
    this.onPostTap,
  });

  static const columns = 3;

  final List<FeedPost> posts;
  final Widget empty;
  final ProfilePostTab? tab;
  final void Function(FeedPost post)? onPostTap;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return empty;
    return GridView.builder(
      // The wall sits inside the profile's own scroll view, so it takes the
      // height its tiles need instead of starting a second scroller.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final tile = switch (tab) {
          ProfilePostTab.images => _ImageTile(post: post),
          ProfilePostTab.videos => const _VideoTile(),
          ProfilePostTab.text => _TextTile(post: post),
          null => _Thumbnail(post: post),
        };
        return _Tappable(post: post, onTap: onPostTap, child: tile);
      },
    );
  }
}

/// The square a tile lives in, and the tap that opens the post when the wall is
/// browsable.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.post,
    required this.onTap,
    required this.child,
  });

  final FeedPost post;
  final void Function(FeedPost post)? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tile = AspectRatio(aspectRatio: 1, child: child);
    final callback = onTap;
    if (callback == null) return tile;
    return InkWell(onTap: () => callback(post), child: tile);
  }
}

/// A still, with a corner badge when the post is a carousel. The badge names the
/// count of slides the tap will open, so a wall of singles stays unmarked.
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slides = post.slides;
    if (slides.isEmpty) return _CaptionTile(post: post);

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: slides.first,
            fit: BoxFit.cover,
            errorListener: (_) {},
            // No spinner: the grey box under it is the placeholder, the way
            // the reference wall shows a tile loading.
            errorWidget: (context, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
          if (slides.length > 1)
            PositionedDirectional(
              top: AppSpacing.xs,
              end: AppSpacing.xs,
              child: _CornerBadge(
                child: Icon(
                  Icons.copy_all_rounded,
                  size: 14,
                  color: theme.colorScheme.surface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A clip: a neutral tile with a play mark, because the post stores no
/// thumbnail and the clip itself must not be downloaded for one.
class _VideoTile extends StatelessWidget {
  const _VideoTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.play_arrow_rounded,
          size: 34,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A caption-only post: the words are the artwork.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) => _CaptionTile(post: post);
}

class _CaptionTile extends StatelessWidget {
  const _CaptionTile({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          post.caption,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
    child: Padding(padding: const EdgeInsets.all(4), child: child),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slides = post.slides;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (slides.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                post.caption,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            CachedNetworkImage(
              imageUrl: slides.first,
              fit: BoxFit.cover,
              errorListener: (_) {},
              // No spinner: the grey box under it is the placeholder, the way
              // the reference wall shows a tile loading.
              errorWidget: (context, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          if (post.mediaType == 'video' && slides.isNotEmpty)
            const PositionedDirectional(
              top: AppSpacing.xs,
              end: AppSpacing.xs,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}
