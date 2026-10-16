import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_saved_stickers.dart';

/// The Saved tab of the chat tray: every sticker this user bookmarked.
///
/// A tile is a reference, so tapping one sends the same id the Stickers tab
/// sends — no upload, no download, and nothing to keep in step with Storage.
/// A long press takes the bookmark off the shelf; the row below the grid says
/// so, because a gesture nobody hinted at is a control nobody finds.
class ChatSavedStickerPicker extends ConsumerWidget {
  const ChatSavedStickerPicker({super.key, required this.onSelected});

  /// Receives the sticker id to send, in the same shape the tray's other
  /// sticker tab uses.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final shelf = ref.watch(savedStickersProvider);
    return switch (shelf) {
      AsyncError() => ErrorStateView(
        message: strings.savedStickersLoadFailed,
        onRetry: () => ref.invalidate(savedStickersProvider),
      ),
      AsyncData(:final value) when value.isEmpty => EmptyStateView(
        icon: Icons.star_outline,
        title: strings.savedStickersEmpty,
        subtitle: strings.savedStickersEmptyHint,
      ),
      AsyncData(:final value) => Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 5,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                for (final sticker in value)
                  _SavedStickerTile(
                    sticker: sticker,
                    onTap: () => onSelected(sticker.stickerId),
                    onLongPress: () => _remove(context, ref, sticker),
                  ),
              ],
            ),
          ),
          _RemoveHint(text: strings.savedStickerRemoveHint),
        ],
      ),
      _ => const LoadingView(),
    };
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    SavedSticker sticker,
  ) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      await ref
          .read(savedStickerRepositoryProvider)
          .remove(sticker.stickerId, userId: userId);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.savedStickerRemoved)),
      );
    } catch (error) {
      debugPrint('Unable to remove a saved sticker: $error');
      messenger.showSnackBar(
        SnackBar(content: Text(strings.savedStickerFailed)),
      );
    }
  }
}

class _SavedStickerTile extends StatelessWidget {
  const _SavedStickerTile({
    required this.sticker,
    required this.onTap,
    required this.onLongPress,
  });

  final SavedSticker sticker;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final asset = sticker.asset;
    return Semantics(
      button: true,
      // The gesture that removes the bookmark, on the tile it removes.
      hint: strings.savedStickerRemoveHint,
      label: strings.removeSavedSticker,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: asset == null
              // Should not happen — the shelf only lists what this build ships
              // — but a tile that paints nothing is honest, unlike one that
              // crashes the tray.
              ? const Icon(Icons.image_not_supported_outlined)
              : ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    semanticLabel: sticker.stickerId,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
        ),
      ),
    );
  }
}

class _RemoveHint extends StatelessWidget {
  const _RemoveHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
