import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';

/// The profile wall: three square columns, no gaps, the shape of the reference
/// design. A post with media shows its first slide; a text post shows its
/// caption, because there is nothing else to show for it.
class ProfilePostGrid extends StatelessWidget {
  const ProfilePostGrid({super.key, required this.posts, required this.empty});

  static const columns = 3;

  final List<FeedPost> posts;
  final Widget empty;

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
      itemBuilder: (context, index) => _Thumbnail(post: posts[index]),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slides = post.slides;

    return AspectRatio(
      aspectRatio: 1,
      child: ColoredBox(
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
      ),
    );
  }
}
