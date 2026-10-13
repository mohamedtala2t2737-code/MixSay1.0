import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

void main() {
  group('ChatRepository.buildConversationId', () {
    test('is stable regardless of participant order', () {
      expect(
        ChatRepository.buildConversationId(['userB', 'userA']),
        ChatRepository.buildConversationId(['userA', 'userB']),
      );
      expect(
        ChatRepository.buildConversationId(['userB', 'userA']),
        '5_userAuserB',
      );
    });

    test('rejects invalid participant pairs', () {
      expect(() => ChatRepository.buildConversationId([]), throwsArgumentError);
      expect(
        () => ChatRepository.buildConversationId(['userA']),
        throwsArgumentError,
      );
      expect(
        () => ChatRepository.buildConversationId(['same', 'same']),
        throwsArgumentError,
      );
      expect(
        () => ChatRepository.buildConversationId(['', 'userA']),
        throwsArgumentError,
      );
    });
  });

  group('ChatMessage.fromData', () {
    test('uses a safe current timestamp when createdAt is absent', () {
      final before = DateTime.now();
      final message = ChatMessage.fromData(
        id: 'message-1',
        conversationId: 'conversation-1',
        data: const {'senderId': 'userA', 'content': 'hello'},
      );
      final after = DateTime.now();

      expect(message.createdAt.isBefore(before), isFalse);
      expect(message.createdAt.isAfter(after), isFalse);
      expect(message.status, 'sent');
    });

    test('reads storage paths and supports legacy media URLs', () {
      final pathMessage = ChatMessage.fromData(
        id: 'message-1',
        conversationId: 'conversation-1',
        data: const {'mediaPath': 'chats/conversation/user/image.jpg'},
      );
      final legacyMessage = ChatMessage.fromData(
        id: 'message-2',
        conversationId: 'conversation-1',
        data: const {'mediaUrl': 'https://example.test/image.jpg'},
      );

      expect(pathMessage.mediaPath, 'chats/conversation/user/image.jpg');
      expect(legacyMessage.mediaPath, 'https://example.test/image.jpg');
    });
  });
}
