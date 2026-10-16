import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The photos of one post, swipeable, with a dot per slide.
///
/// A single slide paints exactly the square image the card always painted: the
/// page view and the dots only appear once a post really carries several
/// photos. In Arabic the row of dots and the swipe direction both mirror,
/// because they inherit the ambient [Directionality].
class PostCarousel extends StatefulWidget {
  const PostCarousel({super.key, required this.urls, this.onDoubleTap});

  final List<String> urls;
  final VoidCallback? onDoubleTap;

  static const double aspectRatio = 1;

  @override
  State<PostCarousel> createState() => _PostCarouselState();
}

class _PostCarouselState extends State<PostCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();

    final media = GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      child: AspectRatio(
        aspectRatio: PostCarousel.aspectRatio,
        child: urls.length == 1
            ? _Photo(url: urls.first)
            : PageView.builder(
                controller: _controller,
                itemCount: urls.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _Photo(url: urls[index]),
              ),
      ),
    );

    if (urls.length == 1) return media;

    return Column(
      children: [
        media,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _Dots(page: _page, count: urls.length),
        ),
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) =>
          ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (context, url, error) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == page
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
