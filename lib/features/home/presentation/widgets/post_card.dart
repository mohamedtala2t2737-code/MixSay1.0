import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/config/app_links.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/confirmation_dialog.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/conversations_view.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/home/presentation/widgets/post_carousel.dart';
import 'package:social_chat/features/home/presentation/widgets/post_comments_sheet.dart';
import 'package:social_chat/features/home/presentation/widgets/post_video.dart';
import 'package:social_chat/features/reports/data/report_repository.dart';
import 'package:social_chat/features/reports/presentation/report_sheet.dart';

/// Instagram-style post: header, caption, media, action row, then counters.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post});

  final FeedPost post;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _liking = false;

  /// The like the card paints while the write is still in flight, or null when
  /// the card has no opinion the feed does not already show. A failed write
  /// clears it, which is what rolls the heart and the number back.
  bool? _guessed;

  bool get _liked => _guessed ?? widget.post.isLiked;

  /// The stored number, moved by the one the tap caused before Firestore has
  /// reported it back.
  int get _likesShown {
    final shown =
        widget.post.likesCount +
        (_liked == widget.post.isLiked ? 0 : (_liked ? 1 : -1));
    return shown < 0 ? 0 : shown;
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A local guess is only needed until the feed catches up with it. This runs
    // inside the rebuild that delivered the new post, so no setState is needed.
    if (_guessed != null && _guessed == widget.post.isLiked) _guessed = null;
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    final s = AppStrings.of(context);
    final stored = widget.post.isLiked;
    // Paint the result before the transaction answers; the heart must follow
    // the finger, not the network.
    setState(() {
      _liking = true;
      _guessed = !stored;
    });
    try {
      await ref.read(feedRepositoryProvider).toggleLike(post: widget.post);
    } catch (error, stackTrace) {
      debugPrint('Unable to update the like: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _guessed = null);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  /// Double-tap likes and never unlikes, so a second accidental burst cannot
  /// take away a like the user meant to give.
  void _doubleTapLike() {
    if (_liked || _liking) return;
    _toggleLike();
  }

  Future<void> _deletePost() async {
    final s = AppStrings.of(context);
    final confirmed = await askConfirmation(
      context,
      title: s.deletePost,
      message: s.deletePostConfirm,
      confirmLabel: s.deletePost,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(feedRepositoryProvider).deletePost(widget.post);
      ref.invalidate(feedPostsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.postDeleted)));
    } catch (error, stackTrace) {
      debugPrint('Unable to delete the post: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    }
  }

  Future<void> _copyText() async {
    final s = AppStrings.of(context);
    final body = widget.post.caption;
    await Clipboard.setData(
      ClipboardData(text: body.isEmpty ? widget.post.displayName : body),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.textCopied)));
  }

  Future<void> _copyLink() async {
    final s = AppStrings.of(context);
    final url = AppLinks.postUrl(widget.post.id);
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.linkCopied)));
  }

  void _openOptions() {
    final s = AppStrings.of(context);
    final isMine = widget.post.authorId == ref.read(currentUserIdProvider);
    final saved = ref.read(savedPostsProvider).contains(widget.post.id);
    final link = AppLinks.postUrl(widget.post.id);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void closeAndRun(void Function() action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Someone else's post is the one place in the feed you can start
              // a thread from; your own gets no such button.
              if (!isMine)
                AppListTile(
                  leading: const Icon(Icons.mail_outline_rounded),
                  title: s.message,
                  onTap: () => closeAndRun(
                    () => messageUser(context, ref, widget.post.authorId),
                  ),
                ),
              AppListTile(
                leading: Icon(
                  Icons.flag_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: s.reportPost,
                onTap: () => closeAndRun(
                  () => showReportSheet(
                    context,
                    target: ReportTarget.post,
                    targetId: widget.post.id,
                  ),
                ),
              ),
              // Hidden until a real domain is configured in AppLinks, so the
              // copied text is never a broken url.
              if (link != null)
                AppListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: s.copyLink,
                  onTap: () => closeAndRun(_copyLink),
                ),
              if (widget.post.caption.isNotEmpty)
                AppListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: s.copyText,
                  onTap: () => closeAndRun(_copyText),
                ),
              AppListTile(
                leading: Icon(
                  saved
                      ? Icons.bookmark_remove_rounded
                      : Icons.bookmark_add_rounded,
                ),
                title: saved ? s.unsavePost : s.savePost,
                onTap: () => closeAndRun(
                  () => ref
                      .read(savedPostsProvider.notifier)
                      .toggle(widget.post.id),
                ),
              ),
              if (isMine)
                AppListTile(
                  leading: Icon(
                    Icons.delete_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: s.deletePost,
                  onTap: () => closeAndRun(_deletePost),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final post = widget.post;
    final saved = ref.watch(savedPostsProvider).contains(post.id);
    final created = post.createdAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          child: Row(
            children: [
              UserAvatar(
                name: post.displayName,
                url: post.avatarUrl,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (post.fullName.isNotEmpty)
                      Text(
                        post.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (created != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(
                    timeAgo(created, isArabic: s.isArabic),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              IconButton(
                tooltip: s.postOptions,
                onPressed: _openOptions,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: _Caption(text: post.caption),
          ),
        _Media(post: post, onDoubleTapLike: _doubleTapLike),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: _liked ? s.unlike : s.like,
                onPressed: _toggleLike,
                icon: Icon(
                  _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _liked ? AppColors.brandPink : null,
                ),
              ),
              IconButton(
                tooltip: s.comments,
                onPressed: () => showPostCommentsSheet(context, post),
                icon: const Icon(Icons.mode_comment_rounded),
              ),
              IconButton(
                tooltip: s.share,
                onPressed: _copyText,
                icon: const Icon(Icons.send_rounded),
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: saved ? s.unsavePost : s.savePost,
                    onPressed: () =>
                        ref.read(savedPostsProvider.notifier).toggle(post.id),
                    icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Both counters stay on the card whatever their value: a post
              // that reads as silent is still a post that exists.
              Text(
                s.likesCount(_likesShown),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (post.commentsCount > 0)
                // The label carries the number, so the counter and the link to
                // the thread are one line.
                TextButton(
                  onPressed: () => showPostCommentsSheet(context, post),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(s.viewAllComments(post.commentsCount)),
                )
              else
                Text(
                  s.noComments,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 8, color: theme.dividerColor),
      ],
    );
  }
}

class _Media extends StatefulWidget {
  const _Media({required this.post, required this.onDoubleTapLike});

  final FeedPost post;

  /// Double-tapping the media likes the post. It never unlikes: an accidental
  /// second double-tap must not silently remove a like the user gave on
  /// purpose.
  final VoidCallback onDoubleTapLike;

  @override
  State<_Media> createState() => _MediaState();
}

class _MediaState extends State<_Media> with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _burst() {
    widget.onDoubleTapLike();
    _heart.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final slides = post.slides;
    if (slides.isEmpty) return const SizedBox(height: 4);

    return Stack(
      children: [
        post.mediaType == 'video'
            ? PostVideo(url: slides.first, onDoubleTap: _burst)
            : PostCarousel(urls: slides, onDoubleTap: _burst),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _heart,
              builder: (context, child) {
                // One burst per double-tap: before it starts and after it ends
                // there is nothing to paint.
                if (!_heart.isAnimating) return const SizedBox.shrink();
                final t = _heart.value;
                return Opacity(
                  opacity: t < 0.6 ? 1 : (1 - t) / 0.4,
                  child: Transform.scale(
                    scale:
                        0.6 +
                        Curves.easeOutBack.transform(t.clamp(0.0, 0.5) * 2) *
                            0.55,
                    child: const Center(
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 88,
                        color: AppColors.brandPink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Caption text that folds to three lines, with the label that says so.
///
/// Whether a caption needs folding is measured rather than guessed, so the
/// label only appears when a line really is hidden at this width and this text
/// scale.
class _Caption extends StatefulWidget {
  const _Caption({required this.text});

  final String text;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  static const _foldedLines = 3;
  bool _expanded = false;

  bool _needsFolding(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: DefaultTextStyle.of(context).style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _foldedLines,
    )..layout(maxWidth: width);
    final hidden = painter.didExceedMaxLines;
    painter.dispose();
    return hidden;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final folded =
            !_expanded && _needsFolding(context, constraints.maxWidth);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: folded || _expanded
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.text,
                maxLines: folded ? _foldedLines : null,
                overflow: folded ? TextOverflow.ellipsis : null,
              ),
              if (folded || _expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? s.seeLess : s.seeMore,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
