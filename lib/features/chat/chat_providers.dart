import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(),
);

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
