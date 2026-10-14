import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Whether an avatar wears a story ring.
enum AvatarStory {
  /// No ring: the plain circle cards, rows and sheets use.
  none,

  /// The brand sweep: there is a story behind this face.
  unseen,

  /// A flat ring: the stories behind it have been opened.
  seen,
}

/// A face, a letter, or the person icon — plus the story ring the feed draws
/// around it. The ring used to be painted by the stories rail itself.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 20,
    this.story = AvatarStory.none,
    this.busy = false,
    this.showPlus = false,
  });

  final String? url;
  final String name;
  final double radius;
  final AvatarStory story;

  /// Spins over the ring while the owner's story is uploading. Ignored when
  /// [story] is [AvatarStory.none], which has no ring to cover.
  final bool busy;

  /// The small badge that offers adding a story. Ignored, like [busy], when
  /// [story] is [AvatarStory.none].
  final bool showPlus;

  static const _band = 3.0;
  static const _gap = 2.0;

  /// Both ring states take the space of the widest band, so switching a rail
  /// entry between seen and unseen never moves the circles beside it.
  double get _outer => radius * 2 + 2 * (_band + _gap + _gap);

  double get _ring => story == AvatarStory.unseen ? _band : _gap;

  @override
  Widget build(BuildContext context) {
    final circle = _Circle(name: name, url: url, radius: radius);
    if (story == AvatarStory.none) return circle;

    final theme = Theme.of(context);
    return SizedBox(
      width: _outer,
      height: _outer,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _outer,
            height: _outer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: story == AvatarStory.unseen ? _sweep : null,
              color: story == AvatarStory.unseen
                  ? null
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Padding(
              padding: EdgeInsets.all(_ring),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_gap),
                  child: circle,
                ),
              ),
            ),
          ),
          if (busy)
            SizedBox(
              width: _outer,
              height: _outer,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          if (showPlus)
            PositionedDirectional(
              bottom: _gap,
              end: _gap,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandBlue,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: _gap,
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
    );
  }

  static const _sweep = SweepGradient(
    colors: [
      AppColors.brandBlue,
      AppColors.brandYellow,
      AppColors.brandPink,
      AppColors.brandPurple,
      AppColors.brandBlue,
    ],
  );
}

class _Circle extends StatelessWidget {
  const _Circle({required this.name, required this.url, required this.radius});

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      backgroundImage: hasImage
          ? CachedNetworkImageProvider(url!, errorListener: (_) {})
          : null,
      child: hasImage
          ? null
          : name.trim().isEmpty
          ? Icon(Icons.person, size: radius, color: theme.colorScheme.primary)
          : Text(
              name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
    );
  }
}
