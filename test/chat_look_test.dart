import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_wallpaper.dart';

/// The chat screen cannot be pumped without Firebase, so what a test can hold
/// this restyle to is the palette it paints with, the wallpaper it puts behind
/// the thread, and that no control appears on screen without something behind
/// it.
///
/// Checked out sources carry CRLF on Windows, so the file is read as one line
/// ending.
final _screenSource = File('lib/features/chat/chat_screen.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

double _lightness(Color color) => HSLColor.fromColor(color).lightness;

void main() {
  group('the palette', () {
    test('a bubble is darker or paler than its text in both themes', () {
      for (final brightness in Brightness.values) {
        for (final outgoing in [true, false]) {
          final contrast =
              (_lightness(AppColors.chatBubble(outgoing, brightness)) -
                      _lightness(AppColors.chatBubbleText(brightness)))
                  .abs();
          expect(
            contrast,
            greaterThan(0.35),
            reason:
                '$outgoing/$brightness bubble and text sit too close to read',
          );
        }
      }
    });

    test('the dark thread is a dark wallpaper and the light one is pale', () {
      expect(
        _lightness(AppColors.chatWallpaper(Brightness.dark)),
        lessThan(0.25),
      );
      expect(
        _lightness(AppColors.chatWallpaper(Brightness.light)),
        greaterThan(0.75),
      );
    });

    test('what I sent reads green, whatever the theme', () {
      for (final brightness in Brightness.values) {
        final hue = HSLColor.fromColor(AppColors.chatBubble(true, brightness))
            .hue;
        expect(
          hue,
          inInclusiveRange(90, 190),
          reason: '$brightness outgoing bubble is not in the green family',
        );
      }
    });

    test('their side is neutral, not a second brand colour', () {
      for (final brightness in Brightness.values) {
        final color = HSLColor.fromColor(
          AppColors.chatBubble(false, brightness),
        );
        expect(
          color.saturation,
          lessThan(0.2),
          reason: '$brightness incoming bubble drifted toward a hue',
        );
      }
    });

    test('calls stay off until Phase 4 is confirmed', () {
      expect(ChatFeatures.calls, isFalse);
    });
  });

  group('the wallpaper', () {
    Future<void> pumpThread(WidgetTester tester, Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: ChatWallpaper(child: Center(child: Text('thread'))),
          ),
        ),
      );
    }

    testWidgets('it keeps the thread on top of it', (tester) async {
      await pumpThread(tester, Brightness.dark);
      expect(find.text('thread'), findsOneWidget);
    });

    Color baseOf(WidgetTester tester) =>
        (tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: find.byType(ChatWallpaper),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration)
            .color!;

    testWidgets('the dark thread gets the dark base', (tester) async {
      await pumpThread(tester, Brightness.dark);
      expect(baseOf(tester), AppColors.chatWallpaperDark);
    });

    testWidgets('the light thread gets the pale base', (tester) async {
      await pumpThread(tester, Brightness.light);
      expect(baseOf(tester), AppColors.chatWallpaperLight);
    });

    testWidgets('the pattern is painted, not a bitmap that can blur', (
      tester,
    ) async {
      await pumpThread(tester, Brightness.dark);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(
        _wallpaperSource.contains('Image.asset'),
        isFalse,
        reason: 'a wallpaper asset would need one file per brightness',
      );
    });
  });

  group('the app bar', () {
    test('the call icons exist only behind the calls flag', () {
      expect(_screenSource, contains('if (ChatFeatures.calls)'));
      expect(_screenSource, contains('tooltip: s.voiceCall'));
      expect(_screenSource, contains('tooltip: s.videoCall'));
    });

    test('it is the dark bar the thread is read against', () {
      expect(_screenSource, contains('AppColors.chatAppBar('));
      expect(_screenSource, contains('foregroundColor: Colors.white'));
    });

    test('no menu row is a row that does nothing', () {
      final declared = RegExp(r'enum _ChatMenuAction \{([^}]*)\}');
      final match = declared.firstMatch(_screenSource);
      expect(match, isNotNull, reason: 'the menu lost its actions');
      for (final name
          in match!
              .group(1)!
              .split(',')
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)) {
        expect(
          _screenSource,
          contains('case _ChatMenuAction.$name:'),
          reason: '$name has no handler',
        );
      }
    });

    test('the thread sits on the wallpaper, not on a gradient', () {
      expect(_screenSource, contains('body: ChatWallpaper('));
      expect(_screenSource.contains('LinearGradient'), isFalse);
    });
  });

  group('the bubbles', () {
    ChatMessage message({
      String senderId = 'me',
      String status = 'sent',
      ChatMessageType type = ChatMessageType.text,
      String content = 'ahlan',
      String? stickerId,
      ChatReply? replyTo,
    }) => ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      senderId: senderId,
      content: content,
      status: status,
      type: type,
      stickerId: stickerId,
      replyTo: replyTo,
      createdAt: DateTime(2026, 10, 15, 9, 30),
    );

    Future<void> pumpBubble(
      WidgetTester tester,
      ChatMessage message, {
      bool isOutgoing = true,
      bool isGroupStart = true,
      VoidCallback? onReplyTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: ChatMessageBubble(
              message: message,
              isOutgoing: isOutgoing,
              currentUserId: 'me',
              otherDisplayName: 'Salma',
              isGroupStart: isGroupStart,
              onReplyTap: onReplyTap,
            ),
          ),
        ),
      );
      // Localizations arrive a frame after pumpWidget.
      await tester.pump();
    }

    Finder bubble(Color color) => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == color,
    );

    BorderRadiusDirectional tailOf(WidgetTester tester, Color color) =>
        (tester.widget<Container>(bubble(color)).decoration! as BoxDecoration)
                .borderRadius!
            as BorderRadiusDirectional;

    testWidgets('the clock and its ticks live inside the bubble', (
      tester,
    ) async {
      await pumpBubble(tester, message());
      final bubbleRect = tester.getRect(
        bubble(AppColors.chatBubble(true, Brightness.light)),
      );
      final clock = tester.getRect(find.text('09:30'));
      expect(clock.right, lessThanOrEqualTo(bubbleRect.right));
      expect(clock.bottom, lessThanOrEqualTo(bubbleRect.bottom));
      expect(tester.widget<Text>(find.text('09:30')).style?.fontSize, 11);
    });

    testWidgets('the tail is the small radius on the sender side', (
      tester,
    ) async {
      await pumpBubble(tester, message());
      final mine = tailOf(tester, AppColors.chatBubble(true, Brightness.light));
      expect(mine.topStart.x, 16);
      expect(mine.topEnd.x, 16);
      expect(mine.bottomEnd.x, 6);
      expect(mine.bottomStart.x, 16);

      await pumpBubble(tester, message(senderId: 'you'), isOutgoing: false);
      final theirs = tailOf(
        tester,
        AppColors.chatBubble(false, Brightness.light),
      );
      expect(theirs.bottomStart.x, 6);
      expect(theirs.bottomEnd.x, 16);
    });

    testWidgets('a run from one sender is tighter than a change of sender', (
      tester,
    ) async {
      await pumpBubble(tester, message(), isGroupStart: true);
      final newSender = tester.getRect(
        bubble(AppColors.chatBubble(true, Brightness.light)),
      );
      await pumpBubble(tester, message(), isGroupStart: false);
      final sameSender = tester.getRect(
        bubble(AppColors.chatBubble(true, Brightness.light)),
      );
      expect(sameSender.top, lessThan(newSender.top));
    });

    testWidgets('a sticker is bare artwork with its time over the corner', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        message(
          content: '',
          type: ChatMessageType.sticker,
          stickerId: 'mixsay-friends/cat',
        ),
      );
      expect(
        bubble(AppColors.chatBubble(true, Brightness.light)),
        findsNothing,
        reason: 'a coloured card behind a sticker reads as a broken photo',
      );
      final picture = tester.getRect(find.byType(Image));
      expect(picture.width, 152);
      final clock = tester.getRect(find.text('09:30'));
      expect(clock.right, lessThanOrEqualTo(picture.right));
      expect(clock.top, greaterThanOrEqualTo(picture.top));
    });

    testWidgets('the quote jumps only when the original is on screen', (
      tester,
    ) async {
      var jumps = 0;
      final reply = message(
        replyTo: const ChatReply(
          messageId: 'm0',
          senderId: 'you',
          content: 'salam',
          type: ChatMessageType.text,
        ),
      );
      await pumpBubble(tester, reply, onReplyTap: () => jumps++);
      expect(find.text('Salma'), findsOneWidget);
      await tester.tap(find.text('salam'));
      await tester.pump();
      expect(jumps, 1);

      // Same message, original not loaded: a quotation, not a dead link.
      await pumpBubble(tester, reply);
      await tester.tap(find.text('salam'));
      await tester.pump();
      expect(jumps, 1);
    });

    test('the screen only offers the jump for a message it has loaded', () {
      expect(_screenSource, contains('loadedIds.contains(quotedId)'));
      expect(_screenSource, contains('onReplyTap: canJumpToQuote'));
    });

    test('a new day is a small centred chip', () {
      expect(_screenSource, contains('if (showDate)'));
      expect(_screenSource, contains('_DateChip('));
      expect(_bubbleSource.contains('brandPurple'), isFalse);
      expect(_bubbleSource.contains('AppColors.chatBubble('), isTrue);
    });

    test('the read receipt is a blue that shows on its own bubble', () {
      for (final brightness in Brightness.values) {
        final hue = HSLColor.fromColor(AppColors.chatTickRead(brightness)).hue;
        expect(hue, inInclusiveRange(180, 260));
        final contrast =
            (_lightness(AppColors.chatTickRead(brightness)) -
                    _lightness(AppColors.chatBubble(true, brightness)))
                .abs();
        expect(
          contrast,
          greaterThan(0.3),
          reason: '$brightness read ticks are lost on the bubble',
        );
      }
    });
  });
}

final _wallpaperSource = File('lib/features/chat/chat_wallpaper.dart')
    .readAsStringSync();

final _bubbleSource = File('lib/features/chat/chat_message_bubble.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');
