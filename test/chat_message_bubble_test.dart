import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

const _me = 'me';
const _other = 'you';

ChatMessage _message({
  String content = 'ahlan',
  String senderId = _me,
  String status = 'sent',
  ChatMessageType type = ChatMessageType.text,
  ChatReply? replyTo,
  bool deletedForEveryone = false,
  List<String> deletedFor = const [],
  DateTime? createdAt,
}) => ChatMessage(
  id: 'm1',
  conversationId: 'c1',
  senderId: senderId,
  content: content,
  status: status,
  type: type,
  replyTo: replyTo,
  deletedForEveryone: deletedForEveryone,
  deletedFor: deletedFor,
  createdAt: createdAt ?? DateTime(2026, 10, 15, 9, 30),
);

Widget _harness(
  ChatMessage message, {
  bool isOutgoing = true,
  VoidCallback? onLongPress,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppStrings.supportedLocales,
  // The bubble aligns itself inside the row it is given, so the harness hands
  // it the full screen width instead of a centered box.
  home: Scaffold(
    body: ChatMessageBubble(
      message: message,
      isOutgoing: isOutgoing,
      currentUserId: _me,
      otherDisplayName: 'Salma',
      onLongPress: onLongPress,
    ),
  ),
);

/// Localizations load asynchronously, so the frame right after pumpWidget is
/// still an empty box. One more pump is what the running app gets for free.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
}

void main() {
  group('bubble side and time', () {
    testWidgets('my message sits on the end side', (tester) async {
      await _show(tester, _harness(_message()));
      // The bubble widget itself fills the row it is given and aligns its
      // content, so the visible bubble is measured through its text.
      final content = tester.getRect(find.text('ahlan'));
      expect(content.center.dx, greaterThan(400));
    });

    testWidgets('their message sits on the start side', (tester) async {
      await _show(
        tester,
        _harness(_message(senderId: _other), isOutgoing: false),
      );
      final content = tester.getRect(find.text('ahlan'));
      expect(content.center.dx, lessThan(400));
    });

    testWidgets('the time under a bubble uses the locale digits', (
      tester,
    ) async {
      await _show(tester, _harness(_message(), locale: const Locale('ar')));
      // 09:30 in Arabic-Indic digits.
      expect(find.text('٠٩:٣٠'), findsOneWidget);
    });
  });

  group('delivery ticks', () {
    testWidgets('sending shows the clock and no ticks for their side', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(status: 'queued', senderId: _other),
          isOutgoing: false,
        ),
      );
      expect(find.byIcon(Icons.access_time), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('a plain send shows one check', (tester) async {
      await _show(tester, _harness(_message()));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('delivered is grey double check, read is blue', (tester) async {
      await _show(tester, _harness(_message(status: 'delivered')));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
        isNot(AppColors.brandBlue),
      );

      await _show(tester, _harness(_message(status: 'read')));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
        AppColors.chatTickRead(Brightness.light),
      );
    });

    testWidgets('a failed send offers retry and delete', (tester) async {
      await _show(tester, _harness(_message(status: 'failed')));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('quoted reply', () {
    testWidgets('shows who was quoted and what they said', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            replyTo: ChatReply(
              messageId: 'm0',
              senderId: _other,
              content: 'mixsay awy',
              type: ChatMessageType.text,
            ),
          ),
        ),
      );
      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('mixsay awy'), findsOneWidget);
    });

    testWidgets('quoting myself says You, not the other name', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            replyTo: ChatReply(
              messageId: 'm0',
              senderId: _me,
              content: 'ahlan',
              type: ChatMessageType.text,
            ),
          ),
        ),
      );
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('quoting a photo names the photo when it has no caption', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(
            replyTo: ChatReply(
              messageId: 'm0',
              senderId: _other,
              content: '',
              type: ChatMessageType.image,
            ),
          ),
        ),
      );
      expect(find.text('Photo'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('a message deleted for everyone becomes a tombstone', (
      tester,
    ) async {
      var longPressed = false;
      await _show(
        tester,
        _harness(
          _message(content: 'secret', deletedForEveryone: true),
          onLongPress: () => longPressed = true,
        ),
      );
      expect(find.text('This message was deleted'), findsOneWidget);
      expect(find.text('secret'), findsNothing);

      await tester.longPress(find.text('This message was deleted'));
      expect(longPressed, isFalse);
    });

    testWidgets('long press opens the message actions', (tester) async {
      var opened = false;
      await _show(
        tester,
        _harness(_message(), onLongPress: () => opened = true),
      );
      await tester.longPress(find.text('ahlan'));
      expect(opened, isTrue);
    });
  });

  group('text direction', () {
    TextDirection? directionOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).textDirection;
    const arabicPhrase = 'إزيك';
    const latinPhrase = 'how are you';

    testWidgets('arabic content reads right to left', (tester) async {
      await _show(tester, _harness(_message(content: arabicPhrase)));
      expect(directionOf(tester, arabicPhrase), TextDirection.rtl);
    });

    testWidgets('latin content keeps the app direction', (tester) async {
      await _show(tester, _harness(_message(content: latinPhrase)));
      expect(directionOf(tester, latinPhrase), isNull);
    });
  });
}
