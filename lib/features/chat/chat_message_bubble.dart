import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';
import 'package:social_chat/features/chat/chat_time_labels.dart';

/// One message in the thread: the bubble, the quoted reply it carries, its
/// time and its delivery ticks.
///
/// A message the sender deleted for everyone is rendered as a tombstone,
/// because the document is still there and both sides have to agree on what
/// happened to it. A message hidden for one side never reaches this widget at
/// all; the chat screen drops it from the list.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    required this.currentUserId,
    required this.otherDisplayName,
    this.imageUrl,
    this.localImagePath,
    this.onRetry,
    this.onDeleteFailed,
    this.onImageTap,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isOutgoing;
  final String currentUserId;
  final String otherDisplayName;
  final Future<String>? imageUrl;
  final String? localImagePath;
  final VoidCallback? onRetry;
  final VoidCallback? onDeleteFailed;
  final VoidCallback? onImageTap;
  final VoidCallback? onLongPress;

  bool get _showsMedia =>
      localImagePath != null ||
      imageUrl != null ||
      message.inferredType() == ChatMessageType.image;

  /// A bundled sticker is the picture itself with no bubble behind it: the
  /// artwork carries its own shape, and a coloured card under it reads as a
  /// photo that failed to load.
  bool get _isBundledSticker =>
      message.type == ChatMessageType.sticker &&
      message.mediaPath == null &&
      message.stickerId != null;

  String _replyAuthorName(AppStrings strings) {
    final reply = message.replyTo;
    if (reply == null) return '';
    return reply.senderId == currentUserId
        ? strings.youLabel
        : otherDisplayName;
  }

  /// The text a quote shows when the quoted message carried no text.
  String _replyPreview(AppStrings strings) {
    final reply = message.replyTo;
    if (reply == null) return '';
    if (reply.content.isNotEmpty) return reply.content;
    return reply.type.previewLabel(strings);
  }

  /// Arabic and Hebrew script read right to left whatever the app language is,
  /// so a single sentence keeps its own shape inside the thread.
  TextDirection? _contentDirection() {
    final rtlScript = RegExp('[\\u0590-\\u08FF]');
    if (!rtlScript.hasMatch(message.content)) return null;
    return TextDirection.rtl;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final bubbleColor = isOutgoing
        ? AppColors.brandPurple
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isOutgoing ? Colors.white : theme.colorScheme.onSurface;

    return Align(
      alignment: isOutgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: Column(
          crossAxisAlignment: isOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: message.deletedForEveryone ? null : onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: _isBundledSticker
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(8),
                decoration: _isBundledSticker
                    ? null
                    : BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadiusDirectional.only(
                          topStart: const Radius.circular(16),
                          topEnd: const Radius.circular(16),
                          bottomStart: Radius.circular(isOutgoing ? 16 : 4),
                          bottomEnd: Radius.circular(isOutgoing ? 4 : 16),
                        ),
                      ),
                child: message.deletedForEveryone
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                            color: textColor.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            strings.messageDeleted,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.replyTo != null)
                            _ReplyQuote(
                              isOutgoing: isOutgoing,
                              author: _replyAuthorName(strings),
                              preview: _replyPreview(strings),
                            ),
                          if (_isBundledSticker)
                            _StickerContent(stickerId: message.stickerId),
                          if (_showsMedia)
                            _ImageContent(
                              localImagePath: localImagePath,
                              imageUrl: imageUrl,
                              onImageTap: onImageTap,
                            ),
                          if (message.content.isNotEmpty)
                            Padding(
                              padding: _showsMedia
                                  ? const EdgeInsets.only(top: 6)
                                  : EdgeInsets.zero,
                              child: Text(
                                message.content,
                                textDirection: _contentDirection(),
                                style: TextStyle(color: textColor),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: isOutgoing ? 0 : 8,
                end: isOutgoing ? 8 : 0,
                bottom: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chatTimeLabel(strings, message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    _StatusTicks(status: message.status),
                  ],
                ],
              ),
            ),
            if (isOutgoing && message.status == 'failed')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(strings.retrySend),
                  ),
                  TextButton.icon(
                    onPressed: onDeleteFailed,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(strings.deleteMessage),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The quoted message shown inside a reply bubble. It is the snapshot that
/// travelled with the new message, so rendering it costs no extra read and it
/// survives the original being deleted.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.isOutgoing,
    required this.author,
    required this.preview,
  });

  final bool isOutgoing;
  final String author;
  final String preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isOutgoing
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.brandPurple;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (isOutgoing ? Colors.white : theme.colorScheme.surface)
            .withValues(alpha: isOutgoing ? 0.16 : 0.6),
        borderRadius: BorderRadius.circular(8),
        border: BorderDirectional(start: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isOutgoing
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture of a bundled sticker, looked up from the id the message
/// carries. An id from a pack this build does not have shows the same
/// placeholder a broken photo does, because the message itself is real.
class _StickerContent extends StatelessWidget {
  const _StickerContent({required this.stickerId});

  final String? stickerId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = chatStickerAssetOf(stickerId);
    if (asset == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.of(context).chatPreviewSticker,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Image.asset(
        asset,
        width: 132,
        height: 132,
        fit: BoxFit.contain,
        semanticLabel: stickerId,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_outlined),
      ),
    );
  }
}

/// The photo inside a bubble: the local file while the send is still queued,
/// the Storage url once it has landed.
class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.localImagePath,
    required this.imageUrl,
    this.onImageTap,
  });

  final String? localImagePath;
  final Future<String>? imageUrl;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final local = localImagePath;
    if (local != null) {
      return GestureDetector(
        onTap: onImageTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(local),
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
              width: double.infinity,
              height: 160,
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    }
    final url = imageUrl;
    if (url == null) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: url,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Icon(Icons.broken_image_outlined);
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: double.infinity,
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          onTap: onImageTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: snapshot.data!,
              width: double.infinity,
              fit: BoxFit.cover,
              memCacheWidth: 440,
              placeholder: (_, _) => const SizedBox(
                width: double.infinity,
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => const SizedBox(
                width: double.infinity,
                height: 160,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusTicks extends StatelessWidget {
  const _StatusTicks({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(
      switch (status) {
        'queued' || 'sending' => Icons.access_time,
        'delivered' || 'read' => Icons.done_all,
        _ => Icons.check,
      },
      size: 15,
      color: status == 'read'
          ? AppColors.brandBlue
          : theme.colorScheme.onSurfaceVariant,
    );
  }
}
