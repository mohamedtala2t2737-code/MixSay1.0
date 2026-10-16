import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// What forwarding a message actually moves into the other chat.
///
/// A forward is a copy of the payload, never of a file: a photo, a clip, a
/// document or a voice note lives in the folder of the chat it was sent to
/// (`chats/{conversationId}/{senderId}/…`), and `storage.rules` lets only the
/// members of *that* chat read it. Reusing such a url would be refused on the
/// write and would show the receiver a broken picture even if it were not, so
/// [from] answers null for those types and the app offers no forward button for
/// a message that cannot travel.
class ChatForwardPayload {
  const ChatForwardPayload({
    required this.type,
    this.text = '',
    this.stickerId,
    this.mediaUrl,
  });

  final ChatMessageType type;

  /// The message itself for a text copy, the caption for the others.
  final String text;

  /// A bundled sticker travels by reference: the receiver's app draws the same
  /// asset from its own pack, so nothing is uploaded and nothing is downloaded.
  final String? stickerId;

  /// A GIF already points at a public url rather than at my Storage, so the
  /// same url is legal in any chat.
  final String? mediaUrl;

  /// The copy this message would produce, or null when it cannot be forwarded.
  ///
  /// [ChatMessage.inferredType] is what decides, so a document written before
  /// messages carried a `type` — which reads as a photo — is correctly refused.
  static ChatForwardPayload? from(ChatMessage message) {
    if (message.deletedForEveryone) return null;
    return switch (message.inferredType()) {
      ChatMessageType.text =>
        message.content.trim().isEmpty
            ? null
            : ChatForwardPayload(
                type: ChatMessageType.text,
                text: message.content,
              ),
      ChatMessageType.sticker =>
        message.stickerId != null && message.mediaPath == null
            ? ChatForwardPayload(
                type: ChatMessageType.sticker,
                text: message.content,
                stickerId: message.stickerId,
              )
            : null,
      ChatMessageType.gif =>
        _publicUrl(message.mediaPath) == null
            ? null
            : ChatForwardPayload(
                type: ChatMessageType.gif,
                text: message.content,
                mediaUrl: _publicUrl(message.mediaPath),
              ),
      _ => null,
    };
  }

  static String? _publicUrl(String? url) =>
      url != null && url.startsWith('https://') ? url : null;
}

/// Where a forward goes: a chat that already exists, or a person whose chat is
/// opened when the copy is sent.
///
/// A new chat is created at send time and not when the row is tapped, so
/// changing your mind in the picker leaves no empty conversation behind.
class ChatForwardTarget {
  const ChatForwardTarget.conversation(this.conversationId) : userId = null;

  const ChatForwardTarget.newChat(this.userId) : conversationId = null;

  final String? conversationId;
  final String? userId;

  bool get isNewChat => conversationId == null;

  /// Ticking the same chat twice has to mean one selection, so two targets that
  /// point at the same place are the same value.
  @override
  bool operator ==(Object other) =>
      other is ChatForwardTarget &&
      other.conversationId == conversationId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(conversationId, userId);
}
