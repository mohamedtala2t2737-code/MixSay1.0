import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';

/// Localizations load asynchronously, so the frame right after pumpWidget is
/// still an empty box.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
}

Widget _harness(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: Scaffold(body: child),
    );

ChatMessage _stickerMessage(String? stickerId) => ChatMessage(
  id: 'm1',
  conversationId: 'c1',
  senderId: 'me',
  content: '',
  status: 'sent',
  type: ChatMessageType.sticker,
  stickerId: stickerId,
  createdAt: DateTime(2026, 10, 15, 9, 30),
);

void main() {
  group('bundled packs', () {
    test('every sticker the manifest lists is really in the app', () {
      for (final pack in chatStickerPacks) {
        for (final sticker in pack.stickers) {
          final asset = 'assets/stickers/${pack.id}/$sticker.png';
          expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
        }
      }
    });

    test('a sticker id stays inside the length the rules allow', () {
      for (final pack in chatStickerPacks) {
        for (final sticker in pack.stickers) {
          // firestore.rules caps stickerId at 120 characters.
          expect(chatStickerId(pack, sticker).length, lessThan(120));
        }
      }
    });
  });

  group('resolving a received id', () {
    test('a known id paints its own asset', () {
      final pack = chatStickerPacks.first;

      expect(
        chatStickerAssetOf(chatStickerId(pack, pack.stickers.first)),
        'assets/stickers/${pack.id}/${pack.stickers.first}.png',
      );
    });

    test('an id from a pack this build lacks paints nothing', () {
      expect(chatStickerAssetOf('holiday-2027/sun'), isNull);
      expect(
        chatStickerAssetOf('${chatStickerPacks.first.id}/not-in-pack'),
        isNull,
      );
    });

    test('a made-up string never becomes an asset path', () {
      expect(chatStickerAssetOf('../../windows/warning'), isNull);
      expect(chatStickerAssetOf('no-slash'), isNull);
      expect(chatStickerAssetOf('/sun'), isNull);
      expect(chatStickerAssetOf('mixsay-friends/'), isNull);
      expect(chatStickerAssetOf(null), isNull);
    });
  });

  test('a queued sticker is still a sticker before it is sent', () {
    final message = ChatMessage.fromPending({
      'client_id': 'c-1',
      'conversation_id': 'conv-1',
      'sender_id': 'me',
      'created_at': DateTime.utc(2026, 3, 4).toIso8601String(),
      'state': 'queued',
      'content': '',
      'sticker_id': 'mixsay-friends/cat',
    });

    expect(message.type, ChatMessageType.sticker);
    expect(message.stickerId, 'mixsay-friends/cat');
    expect(message.mediaPath, isNull);
  });

  group('the tray', () {
    testWidgets('tapping a sticker reports its id', (tester) async {
      String? sent;
      await _show(
        tester,
        _harness(ChatStickerPicker(onSelected: (id) => sent = id)),
      );

      await tester.tap(find.byType(Image).first);

      expect(sent, chatStickerId(chatStickerPacks.first, 'sun'));
    });

    testWidgets('the pack is named in the language in use', (tester) async {
      await _show(
        tester,
        _harness(
          ChatStickerPicker(onSelected: (_) {}),
          locale: const Locale('ar'),
        ),
      );

      expect(find.text(chatStickerPacks.first.nameAr), findsOneWidget);
    });
  });

  group('a sticker in the thread', () {
    testWidgets('the picture is shown with no bubble behind it', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          ChatMessageBubble(
            message: _stickerMessage('mixsay-friends/cat'),
            isOutgoing: true,
            currentUserId: 'me',
            otherDisplayName: 'Salma',
          ),
        ),
      );

      final painted = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/stickers/mixsay-friends/cat.png',
      );
      expect(painted, findsOneWidget);
      expect(tester.widget<Image>(painted).width, 132);
    });

    testWidgets('a sticker from a newer pack says so instead of breaking', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          ChatMessageBubble(
            message: _stickerMessage('holiday-2027/snowman'),
            isOutgoing: false,
            currentUserId: 'me',
            otherDisplayName: 'Salma',
          ),
        ),
      );

      expect(find.text('Sticker'), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });
  });
}
