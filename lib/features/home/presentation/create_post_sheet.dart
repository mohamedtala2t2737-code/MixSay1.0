import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/picked_image.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';

/// Opens the create-post sheet; the bottom bar centre button and the empty
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
  PickedImage? _image;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_busy) return;
    final picked = await pickAndCompressImage();
    if (picked != null && mounted) setState(() => _image = picked);
  }

  Future<void> _publish() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final caption = _controller.text.trim();
    final image = _image;
    if (caption.isEmpty && image == null) return;

    setState(() => _busy = true);
    String? mediaUrl;
    try {
      final repository = ref.read(feedRepositoryProvider);
      final postId = repository.newPostId();
      if (image != null) {
        mediaUrl = await repository.uploadPostMedia(
          postId: postId,
          bytes: image.bytes,
          contentType: image.contentType,
          extension: image.extension,
        );
      }
      await repository.createPost(
        postId: postId,
        caption: caption,
        mediaUrl: mediaUrl,
        mediaType: mediaUrl == null ? 'none' : 'image',
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
    final profile = ref.watch(currentProfileProvider).value;
    final image = _image;

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
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Stack(
                  alignment: AlignmentDirectional.topEnd,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        image.bytes,
                        height: 200,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: IconButton(
                        tooltip: s.cancel,
                        onPressed: () => setState(() => _image = null),
                        icon: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: s.attachPhoto,
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                if (image != null)
                  TextButton(onPressed: _pickImage, child: Text(s.attachPhoto)),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      // A hard 150 clipped "جارٍ النشر..." at large text
                      // scales; the button now keeps its floor but can grow.
                      constraints: const BoxConstraints(minWidth: 150),
                      child: PrimaryButton(
                        label: _busy ? s.publishing : s.publish,
                        loading: _busy,
                        onPressed:
                            _controller.text.trim().isEmpty && image == null
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
