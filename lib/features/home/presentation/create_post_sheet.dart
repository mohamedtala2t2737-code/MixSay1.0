import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_radius.dart';
import 'package:social_chat/core/utils/picked_media.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';

/// Opens the create-post sheet; the bottom bar centre item and the empty
/// states both route here.
Future<void> showCreatePostSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: const _CreatePostSheet(),
    ),
  );
}

class _CreatePostSheet extends ConsumerStatefulWidget {
  const _CreatePostSheet();

  @override
  ConsumerState<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends ConsumerState<_CreatePostSheet> {
  final _controller = TextEditingController();

  /// The attached photos (a carousel) or the single attached clip.
  List<PickedPostMedia> _media = const [];
  bool _busy = false;
  double _progress = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reportFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick({required bool video}) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      // A photo pick replaces the whole set: mixing a clip into a carousel is
      // what the `mediaType == 'image'` rule refuses, so the picker does not
      // offer it.
      final picked = video ? [?await pickPostVideo()] : await pickPostImages();
      if (picked.isNotEmpty && mounted) setState(() => _media = picked);
    } on PostMediaException catch (failure) {
      if (mounted) {
        _reportFailure(
          failure.reason == PostMediaFailure.tooLarge
              ? s.mediaTooLarge
              : s.mediaUnsupported,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to attach media to the post: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _reportFailure(s.actionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeSlide(int index) {
    final next = List<PickedPostMedia>.from(_media)..removeAt(index);
    setState(() => _media = next);
  }

  Future<void> _publish() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final caption = _controller.text.trim();
    final media = _media;
    if (caption.isEmpty && media.isEmpty) return;

    setState(() {
      _busy = true;
      _progress = 0;
    });
    final uploaded = <String>[];
    try {
      final repository = ref.read(feedRepositoryProvider);
      final postId = repository.newPostId();
      for (var index = 0; index < media.length; index++) {
        final url = await repository.uploadPostMedia(
          postId: postId,
          media: media[index],
          slide: index,
          // One bar for the whole set: the fraction is the share of the files
          // that are finished plus the part of the current one that is.
          onProgress: (fraction) {
            if (mounted) {
              setState(() => _progress = (index + fraction) / media.length);
            }
          },
        );
        uploaded.add(url);
      }
      await repository.createPost(
        postId: postId,
        caption: caption,
        mediaUrls: uploaded,
        mediaType: media.isEmpty ? 'none' : media.first.mediaType,
      );
      ref.invalidate(feedPostsProvider);
      if (!mounted) return;
      // The messenger belongs to the app, not to this sheet, so grab it before
      // popping: after the pop this widget's context is defunct.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.postPublished)));
    } catch (error, stackTrace) {
      debugPrint('Unable to publish the post: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Nothing links these files yet, so a half-published post would leave
      // them unreachable forever.
      for (final url in uploaded) {
        try {
          await ref.read(feedRepositoryProvider).deleteUnpublishedMedia(url);
        } catch (cleanupError, cleanupTrace) {
          debugPrint('Unable to clean up post media: $cleanupError');
          debugPrintStack(stackTrace: cleanupTrace);
        }
      }
      if (mounted) {
        setState(() => _busy = false);
        // Which half broke matters. The files failing is a connection problem
        // the user can retry; the saved post failing is the server rules
        // refusing the shape, where retrying changes nothing.
        if (error is PostRejectedException) {
          _reportFailure(s.postRejectedByRules);
        } else if (media.isEmpty) {
          _reportFailure(s.actionFailed);
        } else {
          _reportFailure(s.uploadFailed);
        }
      }
    }
  }

  Widget _preview(AppStrings s) {
    final media = _media;
    if (media.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: media.first.isVideo
          // A clip cannot be thumbnailed without another dependency, so the
          // sheet shows what the user actually chose.
          ? Stack(
              alignment: AlignmentDirectional.topEnd,
              children: [
                _VideoPreview(media: media.first),
                _ClearButton(
                  tooltip: s.cancel,
                  onPressed: () => setState(() => _media = const []),
                ),
              ],
            )
          : SizedBox(
              // Thumbs carry no text, so a fixed height cannot clip anything at
              // a large text scale.
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _SlideThumb(
                  media: media[index],
                  position: index + 1,
                  onRemove: () => _removeSlide(index),
                  tooltip: s.cancel,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final media = _media;
    final percent = (_progress * 100).clamp(0, 100).round();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: profile?.fullName ?? profile?.username ?? '',
                  url: profile?.avatarUrl,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.createPost,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 2,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.postCaptionHint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
            _preview(s),
            if (_busy && media.isNotEmpty && _progress > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.chipBorder,
                      child: LinearProgressIndicator(value: _progress),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.uploadProgress(percent),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: s.attachPhoto,
                  onPressed: _busy ? null : () => _pick(video: false),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: s.attachVideo,
                  onPressed: _busy ? null : () => _pick(video: true),
                  icon: const Icon(Icons.video_library_outlined),
                ),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      // A hard 150 clipped "جارٍ النشر…" at large text scales;
                      // the button keeps its floor but can grow.
                      constraints: const BoxConstraints(minWidth: 150),
                      child: PrimaryButton(
                        label: _busy ? s.publishing : s.publish,
                        loading: _busy,
                        onPressed:
                            _controller.text.trim().isEmpty && media.isEmpty
                            ? null
                            : _publish,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The X that sits on the top-end corner of a preview.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.scrim.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        color: theme.colorScheme.surface,
        icon: const Icon(Icons.close_rounded, size: 18),
      ),
    );
  }
}

/// One attached photo in the composer strip, numbered so the order the user
/// picked in is the order the carousel will show.
class _SlideThumb extends StatelessWidget {
  const _SlideThumb({
    required this.media,
    required this.position,
    required this.tooltip,
    required this.onRemove,
  });

  final PickedPostMedia media;
  final int position;
  final String tooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = media.bytes;

    return SizedBox(
      width: 104,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: AppRadius.smBorder,
            child: bytes == null
                ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                : Image.memory(bytes, fit: BoxFit.cover),
          ),
          PositionedDirectional(
            top: 4,
            start: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.scrim.withValues(alpha: 0.5),
                borderRadius: AppRadius.chipBorder,
              ),
              child: Text(
                AppStrings.of(context).number(position),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.surface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: _ClearButton(tooltip: tooltip, onPressed: onRemove),
          ),
        ],
      ),
    );
  }
}

/// A clip cannot be thumbnailed without another dependency, so the sheet shows
/// what the user actually chose: the file name and its size.
class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.media});

  final PickedPostMedia media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeMb = (media.sizeBytes / (1024 * 1024)).ceil();

    return Container(
      // A floor, not a fixed height: the name and size lines grow with the
      // system text scale and would be clipped at 120.
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.mdBorder,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.movie_outlined, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.name.isEmpty ? 'video.${media.extension}' : media.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppStrings.of(context).number(sizeMb)} MB',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
