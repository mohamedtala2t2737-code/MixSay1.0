import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
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
  PickedPostMedia? _media;
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
      final picked = video ? await pickPostVideo() : await pickPostImage();
      if (picked != null && mounted) setState(() => _media = picked);
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

  Future<void> _publish() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final caption = _controller.text.trim();
    final media = _media;
    if (caption.isEmpty && media == null) return;

    setState(() {
      _busy = true;
      _progress = 0;
    });
    String? mediaUrl;
    try {
      final repository = ref.read(feedRepositoryProvider);
      final postId = repository.newPostId();
      if (media != null) {
        mediaUrl = await repository.uploadPostMedia(
          postId: postId,
          media: media,
          onProgress: (fraction) {
            if (mounted) setState(() => _progress = fraction);
          },
        );
      }
      await repository.createPost(
        postId: postId,
        caption: caption,
        mediaUrl: mediaUrl,
        mediaType: media?.mediaType ?? 'none',
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
      if (mediaUrl != null) {
        try {
          await ref
              .read(feedRepositoryProvider)
              .deleteUnpublishedMedia(mediaUrl);
        } catch (cleanupError, cleanupTrace) {
          debugPrint('Unable to clean up post media: $cleanupError');
          debugPrintStack(stackTrace: cleanupTrace);
        }
      }
      if (mounted) {
        setState(() => _busy = false);
        // A media failure is worth naming: the user needs to know the upload,
        // not the post, is what broke.
        _reportFailure(media == null ? s.actionFailed : s.uploadFailed);
      }
    }
  }

  Widget _preview(AppStrings s, PickedPostMedia media) {
    final bytes = media.bytes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        alignment: AlignmentDirectional.topEnd,
        children: [
          if (bytes != null && !media.isVideo)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                height: 200,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            )
          else
            _VideoPreview(media: media),
          Padding(
            padding: const EdgeInsets.all(6),
            child: IconButton(
              tooltip: s.cancel,
              onPressed: () => setState(() => _media = null),
              icon: const CircleAvatar(
                radius: 14,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
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
            if (media != null) _preview(s, media),
            if (_busy && media != null && _progress > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
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
                            _controller.text.trim().isEmpty && media == null
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
        borderRadius: BorderRadius.circular(12),
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
