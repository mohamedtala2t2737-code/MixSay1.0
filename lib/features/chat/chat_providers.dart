import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_saved_stickers.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ageGroups: ref.watch(ageGroupServiceProvider)),
);

final savedStickerRepositoryProvider = Provider<SavedStickerRepository>(
  (ref) => SavedStickerRepository(),
);

/// The sticker shelf, newest save first, already dropped to the rows this build
/// can draw.
final savedStickersProvider = StreamProvider.autoDispose<List<SavedSticker>>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream.error(StateError('Sign in to save stickers'));
  }
  return ref.watch(savedStickerRepositoryProvider).watchSaved(userId: userId);
});

final conversationsProvider =
    StreamProvider.autoDispose<List<ChatConversationPreview>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        return Stream.error(StateError('Sign in with Firebase to use chat'));
      }
      return ref
          .watch(chatRepositoryProvider)
          .watchConversations(userId: userId);
    });
