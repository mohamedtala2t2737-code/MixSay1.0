import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_media.dart';
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
    this.thumbnailUrl,
    this.voicePlayback,
    this.fileProgress,
    this.onRetry,
    this.onDeleteFailed,
    this.onImageTap,
    this.onVideoTap,
    this.onVoiceTap,
    this.onFileTap,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isOutgoing;
  final String currentUserId;
  final String otherDisplayName;
  final Future<String>? imageUrl;
  final String? localImagePath;

  /// The poster for a video message, which is a second Storage object beside
  /// the clip. Null until the screen has a signed url for it.
  final Future<String>? thumbnailUrl;

  /// Where the voice note this bubble shows has got to. Only the message the
  /// chat screen is playing gets one; every other bubble is handed null, which
  /// is what lets one player serve a whole thread.
  final ChatVoicePlayback? voicePlayback;

  /// 0..1 while a received document is being downloaded, null when it is not.
  final double? fileProgress;
  final VoidCallback? onRetry;
  final VoidCallback? onDeleteFailed;
  final VoidCallback? onImageTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onFileTap;
  final VoidCallback? onLongPress;

  bool get _showsMedia =>
      localImagePath != null ||
      imageUrl != null ||
      message.inferredType() == ChatMessageType.image;

  /// A sticker is the picture itself with no bubble behind it: the artwork
  /// carries its own shape, and a coloured card under it reads as a photo that
  /// failed to load. That holds whether the id came from a bundled pack or the
  /// sender uploaded the picture themselves.
  bool get _isSticker => message.type == ChatMessageType.sticker;

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

  /// The picture, clip, note or file the message carries, or null for a plain
  /// message. Choosing here rather than in the widget tree keeps the bubble one
  /// block plus an optional caption, whatever the type.
  Widget? _mediaBlock() {
    final type = message.type;
    if (type == ChatMessageType.sticker && message.mediaPath == null) {
      return _StickerContent(stickerId: message.stickerId);
    }
    if (type == ChatMessageType.video) {
      return _VideoContent(
        thumbnailUrl: thumbnailUrl,
        durationMs: message.durationMs,
        onTap: onVideoTap,
      );
    }
    if (type == ChatMessageType.voice) {
      return _VoiceContent(
        isOutgoing: isOutgoing,
        durationMs: message.durationMs,
        playback: voicePlayback,
        onTap: onVoiceTap,
      );
    }
    if (type == ChatMessageType.file) {
      return _FileContent(
        fileName: message.fileName,
        fileSize: message.fileSize,
        progress: fileProgress,
        isOutgoing: isOutgoing,
        onTap: onFileTap,
      );
    }
    if (_showsMedia) {
      return _ImageContent(
        localImagePath: localImagePath,
        imageUrl: imageUrl,
        isGif: type == ChatMessageType.gif,
        onImageTap: onImageTap,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final bubbleColor = isOutgoing
        ? AppColors.brandPurple
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isOutgoing ? Colors.white : theme.colorScheme.onSurface;
    final media = message.deletedForEveryone ? null : _mediaBlock();

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
                padding: _isSticker ? EdgeInsets.zero : const EdgeInsets.all(8),
                decoration: _isSticker
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
                          ?media,
                          if (message.content.isNotEmpty)
                            Padding(
                              padding: media != null
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

/// The picture inside a bubble: the local file while the send is still queued,
/// the Storage url once it has landed. A GIF takes the same path — the sender
/// already handed a public url — and is only marked so it reads as animated.
class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.localImagePath,
    required this.imageUrl,
    required this.isGif,
    this.onImageTap,
  });

  final String? localImagePath;
  final Future<String>? imageUrl;
  final bool isGif;
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
            child: Stack(
              children: [
                CachedNetworkImage(
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
                if (isGif)
                  const PositionedDirectional(
                    bottom: 6,
                    start: 6,
                    child: _MediaBadge(label: 'GIF'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The label pinned to the corner of a media tile: a clip's length, or the fact
/// that a picture moves.
class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A clip the receiver can open. The poster is a separate Storage object the
/// sender uploaded beside the video, so reading a thread never downloads a clip
/// just to show what it looks like. While the send is still in flight there is
/// no poster yet, so the tile carries the length alone.
class _VideoContent extends StatelessWidget {
  const _VideoContent({
    required this.thumbnailUrl,
    required this.durationMs,
    this.onTap,
  });

  final Future<String>? thumbnailUrl;
  final int? durationMs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final url = thumbnailUrl;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 220,
          height: 160,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url == null)
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.movie_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                FutureBuilder<String>(
                  future: url,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Icon(Icons.broken_image_outlined);
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return CachedNetworkImage(
                      imageUrl: snapshot.data!,
                      fit: BoxFit.cover,
                      memCacheWidth: 440,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    );
                  },
                ),
              Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: 44,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              PositionedDirectional(
                bottom: 6,
                end: 6,
                child: _MediaBadge(
                  label: chatMediaDurationLabel(strings, durationMs),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the one voice note the thread is playing has got to.
///
/// The chat screen owns the single player and hands this state to exactly one
/// bubble, so tapping a second note takes the player over instead of two clips
/// playing on top of each other.
class ChatVoicePlayback {
  const ChatVoicePlayback({
    this.isPlaying = false,
    this.isLoading = false,
    this.progress = 0,
    this.durationMs,
  });

  final bool isPlaying;

  /// True while the clip url is still being resolved or the audio is buffering.
  final bool isLoading;

  /// 0..1 through the note.
  final double progress;

  /// The player's own length, which wins over the label the sender recorded
  /// when the two disagree.
  final int? durationMs;
}

/// A voice note: the play button, how far it has got, and how long it runs.
class _VoiceContent extends StatelessWidget {
  const _VoiceContent({
    required this.isOutgoing,
    required this.durationMs,
    required this.playback,
    this.onTap,
  });

  final bool isOutgoing;
  final int? durationMs;
  final ChatVoicePlayback? playback;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final current = playback;
    final accent = isOutgoing ? Colors.white : AppColors.brandPurple;
    final track = isOutgoing
        ? Colors.white.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;
    return Semantics(
      button: true,
      label: current?.isPlaying == true
          ? strings.pauseVoiceMessage
          : strings.playVoiceMessage,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              current?.isLoading == true
                  ? Icons.hourglass_empty
                  : current?.isPlaying == true
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_outline,
              size: 32,
              color: accent,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (current?.progress ?? 0).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: track,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              chatMediaDurationLabel(
                strings,
                current?.durationMs ?? durationMs,
              ),
              style: TextStyle(
                fontSize: 11,
                color: isOutgoing
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A document: its name, its size, and how the download is going. The name was
/// written by the sender, so it goes through [chatSafeReceivedName] before it
/// reaches the screen.
class _FileContent extends StatelessWidget {
  const _FileContent({
    required this.fileName,
    required this.fileSize,
    required this.progress,
    required this.isOutgoing,
    this.onTap,
  });

  final String? fileName;
  final int? fileSize;
  final double? progress;
  final bool isOutgoing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final accent = isOutgoing ? Colors.white : AppColors.brandPurple;
    final track = isOutgoing
        ? Colors.white.withValues(alpha: 0.35)
        : theme.colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 30, color: accent),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chatSafeReceivedName(fileName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isOutgoing
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (fileSize != null)
                    Text(
                      strings.chatSizeLimit(fileSize!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOutgoing
                            ? Colors.white70
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: track,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              progress == null
                  ? Icons.download_outlined
                  : Icons.hourglass_empty,
              size: 20,
              color: accent,
            ),
          ],
        ),
      ),
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
