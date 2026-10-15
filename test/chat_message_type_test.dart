import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// The shapes `firestore.rules` validates. A field the rules do not know about
/// is a rejected send, so the payload builder is pinned here the way the
/// emulator suite pins the server side.
void main() {
  group('ChatMessageType.fromWire', () {
    test('reads every type the rules accept', () {
      for (final type in ChatMessageType.values) {
        expect(ChatMessageType.fromWire(type.wireValue), type);
      }
    });

    test('falls back to text for anything unknown', () {
      expect(ChatMessageType.fromWire('location'), ChatMessageType.text);
      expect(ChatMessageType.fromWire(null), ChatMessageType.text);
      expect(ChatMessageType.fromWire(7), ChatMessageType.text);
    });
  });

  group('ChatMessageType', () {
    test('only text and a bundled sticker need no upload', () {
      expect(ChatMessageType.text.needsMedia, isFalse);
      expect(ChatMessageType.sticker.needsMedia, isFalse);
      expect(ChatMessageType.image.needsMedia, isTrue);
      expect(ChatMessageType.gif.needsMedia, isTrue);
    });

    test('hides every gated type under the free plan defaults', () {
      expect(ChatMessageType.text.isGated, isFalse);
      expect(ChatMessageType.sticker.isGated, isFalse);
      expect(ChatMessageType.image.isGated, isTrue);
      expect(ChatMessageType.video.isGated, isTrue);
      expect(ChatMessageType.file.isGated, isTrue);
      expect(ChatMessageType.voice.isGated, isTrue);
      expect(ChatMessageType.gif.isGated, isTrue);
    });

    test('names the media kinds in the locale of the list', () {
      const arabic = AppStrings(Locale('ar'));
      const english = AppStrings(Locale('en'));
      expect(ChatMessageType.image.previewLabel(arabic), 'صورة');
      expect(ChatMessageType.voice.previewLabel(arabic), 'رسالة صوتية');
      expect(ChatMessageType.image.previewLabel(english), 'Photo');
      expect(ChatMessageType.text.previewLabel(english), 'Message');
    });
  });

  group('ChatMessage.fromData', () {
    test('reads the attachment fields', () {
      final message = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: const {
          'senderId': 'me',
          'type': 'video',
          'mediaUrl': 'chats/c1/me/m1.mp4',
          'thumbUrl': 'chats/c1/me/m1.jpg',
          'fileName': 'clip.mp4',
          'fileSize': 4096,
          'durationMs': 12000,
          'replyTo': {
            'messageId': 'm0',
            'senderId': 'you',
            'content': 'hi',
            'type': 'text',
          },
        },
      );

      expect(message.type, ChatMessageType.video);
      expect(message.mediaPath, 'chats/c1/me/m1.mp4');
      expect(message.thumbUrl, 'chats/c1/me/m1.jpg');
      expect(message.fileName, 'clip.mp4');
      expect(message.fileSize, 4096);
      expect(message.durationMs, 12000);
      expect(message.replyTo?.messageId, 'm0');
      expect(message.replyTo?.content, 'hi');
    });

    test('a document written before the type field still labels as media', () {
      final legacy = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: const {'mediaUrl': 'chats/c1/me/m1.jpg'},
      );
      expect(legacy.type, ChatMessageType.text);
      expect(legacy.inferredType(), ChatMessageType.image);
    });

    test('knows who hid a message', () {
      final hidden = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: const {'deletedFor': ['me'], 'senderId': 'you'},
      );
      expect(hidden.hiddenFor('me'), isTrue);
      expect(hidden.hiddenFor('you'), isFalse);

      final gone = ChatMessage.fromData(
        id: 'm2',
        conversationId: 'c1',
        data: const {'deletedForEveryone': true},
      );
      expect(gone.hiddenFor('me'), isTrue);
      expect(gone.hiddenFor('you'), isTrue);
    });

    test('ignores a malformed reply quote instead of throwing', () {
      final message = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: const {'replyTo': {'senderId': 'you'}},
      );
      expect(message.replyTo, isNull);
    });
  });

  group('ChatReply.quoteFrom', () {
    test('copies the quoted text and its author', () {
      final original = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: const {'senderId': 'you', 'content': 'ahlan'},
      );
      final reply = ChatReply.quoteFrom(original);
      expect(reply.messageId, 'm1');
      expect(reply.senderId, 'you');
      expect(reply.content, 'ahlan');
      expect(reply.toMap()['type'], 'text');
    });

    test('cuts the quote at the length the rules allow', () {
      final long = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: {'senderId': 'you', 'content': '😀a' * 400},
      );
      final reply = ChatReply.quoteFrom(long);
      expect(reply.content.runes.length, ChatReply.maxContentLength);
      // 150 whole repeats: the cut lands on a boundary, so no emoji is split
      // in half.
      expect(reply.content, '😀a' * 150);
    });

    test('a quote that ends inside an emoji still keeps it whole', () {
      final long = ChatMessage.fromData(
        id: 'm1',
        conversationId: 'c1',
        data: {'senderId': 'you', 'content': 'a' * 299 + '😀b'},
      );
      final reply = ChatReply.quoteFrom(long);
      // The 300th code point is the emoji itself, kept whole rather than
      // cut into a lone surrogate.
      expect(reply.content, 'a' * 299 + '😀');
    });
  });

  group('ChatRepository.messageFields', () {
    Map<String, dynamic> fields({
      ChatMessageType type = ChatMessageType.text,
      String content = 'ahlan',
      String? mediaPath,
      String? fileName,
      int? fileSize,
      int? durationMs,
      String? stickerId,
      ChatReply? replyTo,
    }) => ChatRepository.messageFields(
      senderId: 'me',
      recipientId: 'you',
      clientId: 'm1',
      content: content,
      type: type,
      mediaPath: mediaPath,
      fileName: fileName,
      fileSize: fileSize,
      durationMs: durationMs,
      stickerId: stickerId,
      replyTo: replyTo,
    );

    test('always writes the seven keys the deployed rules require', () {
      expect(
        fields().keys,
        containsAll(<String>[
          'senderId',
          'recipientId',
          'clientId',
          'content',
          'mediaUrl',
          'createdAt',
          'status',
        ]),
      );
    });

    test('leaves an unused optional out instead of writing null', () {
      final plain = fields();
      expect(plain.containsKey('fileName'), isFalse);
      expect(plain.containsKey('replyTo'), isFalse);
      expect(plain['mediaUrl'], isNull);
      expect(plain['status'], 'sent');
      expect(plain['type'], 'text');
    });

    test('an image carries its own upload path', () {
      final image = fields(
        type: ChatMessageType.image,
        content: '',
        mediaPath: 'chats/c1/me/m1.jpg',
      );
      expect(image['type'], 'image');
      expect(image['mediaUrl'], 'chats/c1/me/m1.jpg');
    });

    test('a file keeps its name and size for the tile', () {
      final file = fields(
        type: ChatMessageType.file,
        content: '',
        mediaPath: 'chats/c1/me/report.pdf',
        fileName: 'report.pdf',
        fileSize: 2048,
      );
      expect(file['fileName'], 'report.pdf');
      expect(file['fileSize'], 2048);
    });

    test('a voice note keeps its duration', () {
      final voice = fields(
        type: ChatMessageType.voice,
        content: '',
        mediaPath: 'chats/c1/me/m1.m4a',
        durationMs: 9000,
      );
      expect(voice['durationMs'], 9000);
    });

    test('a sticker names its asset and uploads nothing', () {
      final sticker = fields(
        type: ChatMessageType.sticker,
        content: '',
        stickerId: 'starter:cat',
      );
      expect(sticker['stickerId'], 'starter:cat');
      expect(sticker['mediaUrl'], isNull);
    });

    test('a reply is written as the four-key map the rules validate', () {
      final quoted = ChatRepository.messageFields(
        senderId: 'me',
        recipientId: 'you',
        clientId: 'm1',
        content: 'رد',
        replyTo: ChatReply(
          messageId: 'm0',
          senderId: 'you',
          content: 'ahlan',
          type: ChatMessageType.text,
        ),
      );
      expect(quoted['replyTo'], {
        'messageId': 'm0',
        'senderId': 'you',
        'content': 'ahlan',
        'type': 'text',
      });
    });

    test('only lists the keys hasOnly allows', () {
      final allowed = <String>{
        'senderId',
        'recipientId',
        'clientId',
        'content',
        'mediaUrl',
        'createdAt',
        'status',
        'type',
        'thumbUrl',
        'fileName',
        'fileSize',
        'durationMs',
        'stickerId',
        'replyTo',
        'deletedFor',
        'deletedForEveryone',
      };
      expect(fields().keys.toSet().difference(allowed), isEmpty);
    });
  });

  group('ChatRepository.conversationFields', () {
    test('keeps the counter increment for the other side', () {
      final fields = ChatRepository.conversationFields(
        recipientId: 'you',
        content: 'ahlan',
        type: ChatMessageType.text,
        senderId: 'me',
      );
      expect(fields['lastMessageContent'], 'ahlan');
      expect(fields['lastMessageType'], 'text');
      expect(fields['lastSenderId'], 'me');
      expect(fields.keys, contains('unreadCounts.you'));
    });

    test('stores no English word for a message with no text', () {
      final fields = ChatRepository.conversationFields(
        recipientId: 'you',
        content: '',
        type: ChatMessageType.voice,
        senderId: 'me',
      );
      expect(fields['lastMessageContent'], isNull);
      expect(fields['lastMessageType'], 'voice');
    });
  });
}
