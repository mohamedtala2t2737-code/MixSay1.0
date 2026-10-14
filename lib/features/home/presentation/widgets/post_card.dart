import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/home/presentation/widgets/post_comments_sheet.dart';

/// Instagram-style post: header, media, action row, then counters and caption.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post});

  final FeedPost post;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _captionExpanded = false;
  bool _liking = false;

  Future<void> _toggleLike() async {
    if (_liking) return;
    final s = AppStrings.of(context);
    setState(() => _liking = true);
    try {
      await ref.read(feedRepositoryProvider).toggleLike(post: widget.post);
    } catch (error, stackTrace) {
      debugPrint('Unable to update the like: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _deletePost() async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deletePost),
        content: Text(s.deletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.deletePost),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

  void _openOptions() {
    final s = AppStrings.of(context);
    final isMine = widget.post.authorId == ref.read(currentUserIdProvider);
    final saved = ref.read(savedPostsProvider).contains(widget.post.id);

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
              ListTile(
                leading: Icon(
                  saved ? Icons.bookmark_remove : Icons.bookmark_add_outlined,
                ),
                title: Text(saved ? s.unsavePost : s.savePost),
                onTap: () => closeAndRun(
                  () => ref
                      .read(savedPostsProvider.notifier)
                      .toggle(widget.post.id),
                ),
              ),
              if (widget.post.caption.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(s.copyText),
                  onTap: () => closeAndRun(_copyText),
                ),
              if (isMine)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(s.deletePost),
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
                  padding: const EdgeInsets.only(right: 4),
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
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
        ),
        _Media(post: post),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: post.isLiked ? s.unlike : s.like,
                onPressed: _toggleLike,
                icon: Icon(
                  post.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: post.isLiked ? AppColors.brandPink : null,
                ),
              ),
              IconButton(
                tooltip: s.comments,
                onPressed: () => showPostCommentsSheet(context, post),
                icon: const Icon(Icons.mode_comment_outlined),
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
              if (post.likesCount > 0)
                Text(
                  s.likesCount(post.likesCount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              if (post.caption.isNotEmpty)
                GestureDetector(
                  onTap: () =>
                      setState(() => _captionExpanded = !_captionExpanded),
                  child: Text(
                    post.caption,
                    maxLines: _captionExpanded ? null : 3,
                    overflow: _captionExpanded ? null : TextOverflow.ellipsis,
                  ),
                ),
              if (post.commentsCount > 0)
                TextButton(
                  onPressed: () => showPostCommentsSheet(context, post),
                  child: Text(s.commentsCount(post.commentsCount)),
                ),
            ],
          ),
        ),
        Divider(height: 8, color: theme.dividerColor),
      ],
    );
  }
}

class _Media extends StatelessWidget {
  const _Media({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = post.mediaUrl;
    if (url == null || url.isEmpty) return const SizedBox(height: 4);
    if (post.mediaType != 'image') {
      // Video posts exist in the schema but the app has no player dependency.
      return SizedBox(
        height: 220,
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 42,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 1,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
        errorWidget: (context, url, error) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}
