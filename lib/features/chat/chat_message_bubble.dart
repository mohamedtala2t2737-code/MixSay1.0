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
    this.onReplyTap,
    this.onSwipeReply,
    this.onForward,
    this.isGroupStart = true,
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

  /// Tapping the quoted block, which is how the thread jumps back to the
  /// message that started it. Null when the screen has that message on hand
  /// nowhere to scroll to, so the block never looks tappable when it is not.
  final VoidCallback? onReplyTap;

  /// Whether the message before this one came from the other side. A group of
  /// one person's messages sits close together and only the first of a group
  /// leaves room, which is what makes a thread readable without names on it.
  final bool isGroupStart;

  /// The small arrow beside a bubble that can travel to another chat. The
  /// screen only hands it over when [ChatForwardPayload.from] says the message
  /// can be copied without uploading anything, so a photo or a voice note —
  /// whose file belongs to the chat it was sent in — has no arrow to press.
  final VoidCallback? onForward;

  /// Answering this message, reached by dragging the bubble sideways. The chat
  /// screen hands it a real reply slot, so the gesture is only armed where the
  /// reply can actually go.
  final VoidCallback? onSwipeReply;

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
    final brightness = theme.brightness;
    final bubbleColor = AppColors.chatBubble(isOutgoing, brightness);
    final textColor = AppColors.chatBubbleText(brightness);
    final timeColor = textColor.withValues(alpha: 0.65);
    final media = message.deletedForEveryone ? null : _mediaBlock();
    // The artwork carries its own shape, so a coloured card under it reads as a
    // photo that failed to load; its time floats over the corner instead.
    final isSticker = _isSticker && media != null;

    final Widget bubble;
    if (isSticker) {
      bubble = Stack(
        children: [
          media,
          PositionedDirectional(
            bottom: 0,
            end: 4,
            child: _TimeChip(
              createdAt: message.createdAt,
              status: message.status,
              isOutgoing: isOutgoing,
            ),
          ),
        ],
      );
    } else {
      bubble = Container(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(isOutgoing ? 16 : 6),
            bottomEnd: Radius.circular(isOutgoing ? 6 : 16),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.replyTo != null)
                _ReplyQuote(
                  isOutgoing: isOutgoing,
                  author: _replyAuthorName(strings),
                  preview: _replyPreview(strings),
                  onTap: onReplyTap,
                ),
              if (message.deletedForEveryone)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.remove_circle_outline,
                      size: 18,
                      color: timeColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      strings.messageDeleted,
                      style: TextStyle(
                        color: timeColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else ...[
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
              // The clock and the ticks live in the bubble's own corner, which
              // is what leaves the thread readable as a run of messages. A Row
              // rather than an Align: Align would take the whole width on offer
              // and stretch the bubble out beside a short message.
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TimeAndStatus(
                    createdAt: message.createdAt,
                    status: message.status,
                    isOutgoing: isOutgoing,
                    color: timeColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Everything that hangs off the bubble's own edge goes in this column, so
    // the label sits over the bubble rather than over the row it shares with
    // the forward arrow.
    final thread = Column(
      crossAxisAlignment: isOutgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        // Beside the bubble rather than inside it: a sticker has no bubble to
        // hold a line of text, and a copy is labelled the same way whether it
        // carries words or artwork.
        if (message.forwarded && !message.deletedForEveryone)
          _ForwardedLabel(textColor: timeColor),
        Padding(
          padding: EdgeInsets.only(top: isGroupStart ? 10 : 2),
          child: _SwipeToReply(
            onReply: onSwipeReply,
            child: GestureDetector(
              onLongPress: message.deletedForEveryone ? null : onLongPress,
              child: bubble,
            ),
          ),
        ),
      ],
    );

    return Align(
      alignment: isOutgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: thread),
                // Beside the bubble rather than in the long-press menu alone:
                // a picture or a sticker has no words to hold a line, and the
                // arrow says what it is without opening anything.
                if (onForward != null)
                  _ForwardArrow(onTap: onForward!, color: timeColor),
              ],
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

/// The clock, and the ticks that say where the message has got to.
class _TimeAndStatus extends StatelessWidget {
  const _TimeAndStatus({
    required this.createdAt,
    required this.status,
    required this.isOutgoing,
    required this.color,
  });

  final DateTime createdAt;
  final String status;
  final bool isOutgoing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          chatTimeLabel(AppStrings.of(context), createdAt),
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (isOutgoing) ...[
          const SizedBox(width: 4),
          _StatusTicks(status: status, color: color),
        ],
      ],
    );
  }
}

/// The same clock on top of a sticker, where there is no bubble to sit in, so
/// it brings its own soft background to stay legible over any artwork.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.createdAt,
    required this.status,
    required this.isOutgoing,
  });

  final DateTime createdAt;
  final String status;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chatTimeLabel(AppStrings.of(context), createdAt),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
          if (isOutgoing)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: _StatusTicks(status: status, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

/// The line that says this bubble is a copy of something said elsewhere. It is
/// a caption rather than a badge: the original message stays where it was, so
/// the only thing worth telling the reader is that these words arrived twice.
class _ForwardedLabel extends StatelessWidget {
  const _ForwardedLabel({required this.textColor});

  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Text(
        AppStrings.of(context).forwardedLabel,
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: textColor,
        ),
      ),
    );
  }
}

/// The arrow that sends this message to another chat. Kept outside the bubble
/// so it never changes the bubble's colour or corner, and quiet enough that a
/// thread of twenty messages does not read as twenty buttons.
class _ForwardArrow extends StatelessWidget {
  const _ForwardArrow({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 2),
      child: Tooltip(
        message: strings.forwardAction,
        child: Semantics(
          button: true,
          label: strings.forwardAction,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.forward, size: 18, color: color),
            ),
          ),
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
    this.onTap,
  });

  final bool isOutgoing;
  final String author;
  final String preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.chatQuoteAccent(brightness);
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.chatBubbleText(brightness)
            .withValues(alpha: isOutgoing ? 0.07 : 0.05),
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
              color: AppColors.chatBubbleText(brightness)
                  .withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      // The message it quotes is not on this screen, so the block stays a
      // quotation rather than pretending to be a link.
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: body);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(onTap: onTap, child: body),
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
        width: 152,
        height: 152,
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

/// What a media control paints with: the bubble's own text colour on my side,
/// and the thread's green on theirs, where a bare icon would read as disabled.
Color _ink(Brightness brightness, bool isOutgoing) => isOutgoing
    ? AppColors.chatBubbleText(brightness)
    : AppColors.chatQuoteAccent(brightness);

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
    final accent = _ink(theme.brightness, isOutgoing);
    final track = AppColors.chatBubbleText(theme.brightness)
        .withValues(alpha: 0.3);
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
                color: AppColors.chatBubbleText(theme.brightness),
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
    final accent = _ink(theme.brightness, isOutgoing);
    final track = AppColors.chatBubbleText(theme.brightness)
        .withValues(alpha: 0.3);
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
                      color: AppColors.chatBubbleText(theme.brightness),
                    ),
                  ),
                  if (fileSize != null)
                    Text(
                      strings.chatSizeLimit(fileSize!),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.chatBubbleText(theme.brightness)
                            .withValues(alpha: 0.7),
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
  const _StatusTicks({required this.status, required this.color});

  final String status;

  /// What the tick looks like before a read receipt arrives. The caller knows
  /// what sits behind it: a bubble's own text colour, or white over a sticker.
  final Color color;

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
          ? AppColors.chatTickRead(theme.brightness)
          : color,
    );
  }
}

/// A bubble pulled sideways and let go answers that message, which is the way
/// most people reply on a phone.
///
/// It only arms when the screen has somewhere for the reply to go, and a swipe
/// works in either direction so an Arabic thread behaves like an English one.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, this.onReply});

  final Widget child;
  final VoidCallback? onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  /// How far the bubble has to travel before the release counts as a reply.
  static const _trigger = 48.0;

  /// The bubble slides a little past that and no further, so a long drag does
  /// not turn into a swipe across the whole screen.
  static const _travel = 72.0;

  double _drag = 0;

  bool get _armed => _drag.abs() >= _trigger;

  void _end(bool fire) {
    setState(() => _drag = 0);
    if (fire) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onReply = widget.onReply;
    if (onReply == null) return widget.child;
    final theme = Theme.of(context);
    // The hint belongs on the side the bubble has just left, which is a matter
    // of pixels rather than of reading direction, so a swipe reads the same in
    // an Arabic thread as in an English one.
    final movedRight = _drag >= 0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => setState(() {
        _drag = (_drag + details.delta.dx).clamp(-_travel, _travel);
      }),
      onHorizontalDragEnd: (_) => _end(_armed),
      onHorizontalDragCancel: () => setState(() => _drag = 0),
      child: Stack(
        children: [
          // Positioned rather than aligned: a hint that grew the stack would
          // move the bubble off its own side of the thread.
          Positioned(
            left: movedRight ? 6 : null,
            right: movedRight ? null : 6,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: movedRight
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Opacity(
                opacity: (_drag.abs() / _trigger).clamp(0.0, 1.0),
                child: Transform(
                  transform: Matrix4.diagonal3Values(movedRight ? -1 : 1, 1, 1),
                  child: Icon(
                    Icons.reply,
                    size: 20,
                    color: AppColors.chatQuoteAccent(theme.brightness),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            transform: Matrix4.translationValues(_drag, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
