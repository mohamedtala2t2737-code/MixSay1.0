import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';

/// Comment thread for one post, opened from the feed card.
Future<void> showPostCommentsSheet(BuildContext context, FeedPost post) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _PostCommentsSheet(post: post),
    ),
  );
}

class _PostCommentsSheet extends ConsumerStatefulWidget {
  const _PostCommentsSheet({required this.post});

  final FeedPost post;

  @override
  ConsumerState<_PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends ConsumerState<_PostCommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final s = AppStrings.of(context);
    setState(() => _sending = true);
    try {
      await ref
          .read(feedRepositoryProvider)
          .addComment(postId: widget.post.id, content: text);
      if (!mounted) return;
      _controller.clear();
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.commentAdded)));
    } catch (error, stackTrace) {
      debugPrint('Unable to add a comment: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final comments = ref.watch(feedCommentsProvider(widget.post.id));

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.comments,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${widget.post.commentsCount}',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: comments.when(
              loading: () => const LoadingView(),
              error: (error, stackTrace) {
                debugPrint('Unable to load comments: $error');
                debugPrintStack(stackTrace: stackTrace);
                return ErrorStateView(
                  message: s.loadFailed,
                  onRetry: () =>
                      ref.invalidate(feedCommentsProvider(widget.post.id)),
                );
              },
              data: (items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.mode_comment_outlined,
                    title: s.noComments,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final comment = items[index];
                    final created = comment.createdAt;
                    return ListTile(
                      dense: true,
                      leading: UserAvatar(name: comment.username, radius: 18),
                      title: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${comment.username} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: comment.content),
                          ],
                        ),
                      ),
                      subtitle: created == null
                          ? null
                          : Text(timeAgo(created, isArabic: s.isArabic)),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: s.writeComment,
                        counterText: '',
                        filled: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : IconButton(
                          tooltip: s.send,
                          onPressed: _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
