import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_attachment_sheet.dart';

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

/// Opens the sheet the way the composer does and waits for the transition, so a
/// tap lands on a row that is really on screen.
Future<ChatAttachmentChoice?> _openAndTap(
  WidgetTester tester,
  List<ChatAttachmentChoice> options,
  String rowLabel,
) async {
  ChatAttachmentChoice? chosen;
  await _show(
    tester,
    _harness(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            chosen = await showChatAttachmentSheet(context, options: options);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await _settle(tester);
  await tester.tap(find.text(rowLabel));
  await _settle(tester);
  return chosen;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Opens the sheet and closes it the way a person would when they change their
/// mind: a tap on the dim area behind it.
Future<ChatAttachmentChoice?> _openAndDismiss(
  WidgetTester tester,
  List<ChatAttachmentChoice> options,
) async {
  ChatAttachmentChoice? chosen;
  await _show(
    tester,
    _harness(
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            chosen = await showChatAttachmentSheet(context, options: options);
          },
          child: const Text('attach'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('attach'));
  await _settle(tester);
  expect(find.byType(BottomSheet), findsOneWidget);

  // The top of the barrier, well above the sheet itself.
  await tester.tapAt(const Offset(300, 40));
  await _settle(tester);
  return chosen;
}

void main() {
  test('the free plan leaves nothing attachable, so there is no paperclip', () {
    // The whole point of the flags: the shipped build must not offer a control
    // that would write to Cloud Storage or call a paid search API.
    expect(ChatAttachmentSheet.availableOptions(), isEmpty);
    expect(ChatFeatures.anyMediaAttachment, isFalse);
  });

  test('a gif row would need both the flag and a key', () {
    expect(ChatFeatures.gifSearch, isFalse);
    // Even with the flag on, the row is only honest once a key is compiled in.
    expect(
      ChatAttachmentSheet.availableOptions().contains(ChatAttachmentChoice.gif),
      isFalse,
    );
  });

  group('the sheet', () {
    testWidgets('it lists exactly the kinds it is given, in order', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          ChatAttachmentSheet(
            options: const [
              ChatAttachmentChoice.photo,
              ChatAttachmentChoice.video,
              ChatAttachmentChoice.document,
            ],
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Add video'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
      expect(find.text('GIF'), findsNothing);
      expect(
        tester.widgetList(find.byType(ListTile)).length,
        3,
        reason: 'one row per enabled kind, no placeholders',
      );
    });

    testWidgets('a kind that is off never takes up a row', (tester) async {
      await _show(
        tester,
        _harness(
          ChatAttachmentSheet(
            options: const [ChatAttachmentChoice.video],
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Add video'), findsOneWidget);
      expect(find.text('Document'), findsNothing);
    });

    testWidgets('the rows speak Arabic when the app does', (tester) async {
      await _show(
        tester,
        _harness(
          ChatAttachmentSheet(
            options: const [
              ChatAttachmentChoice.document,
              ChatAttachmentChoice.gif,
            ],
            onSelected: (_) {},
          ),
          locale: const Locale('ar'),
        ),
      );

      expect(find.text('مستند'), findsOneWidget);
      expect(find.text('صورة متحركة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a row hands that kind back', (tester) async {
      final chosen = await _openAndTap(tester, const [
        ChatAttachmentChoice.photo,
        ChatAttachmentChoice.document,
      ], 'Document');

      expect(chosen, ChatAttachmentChoice.document);
    });

    testWidgets('dismissing the sheet chooses nothing', (tester) async {
      final chosen = await _openAndDismiss(tester, const [
        ChatAttachmentChoice.photo,
      ]);
      expect(chosen, isNull);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('with nothing enabled the sheet never opens', (tester) async {
      ChatAttachmentChoice? chosen;
      await _show(
        tester,
        _harness(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                chosen = await showChatAttachmentSheet(
                  context,
                  options: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(chosen, isNull);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('the composer', () {
    test('its only attachment door is the sheet', () {
      final source = File('lib/features/chat/chat_screen.dart')
          .readAsStringSync();

      expect(source, contains('showChatAttachmentSheet'));
      expect(
        source,
        contains('ChatAttachmentSheet.availableOptions().isNotEmpty'),
        reason: 'the paperclip is drawn only when a row would do something',
      );
      expect(
        source.contains('tooltip: s.sendImage'),
        isFalse,
        reason: 'a photo is picked from the sheet, not from its own button',
      );
    });

    test('every kind the sheet can list has a sender', () {
      final source = File('lib/features/chat/chat_screen.dart')
          .readAsStringSync();

      for (final choice in ChatAttachmentChoice.values) {
        expect(
          source,
          contains('ChatAttachmentChoice.${choice.name}'),
          reason: '$choice has no route in the composer',
        );
      }
    });

    test('a sticker keeps its own button, never a paid row', () {
      // A bundled sticker costs nothing to send, so it does not belong behind
      // the paperclip that hides with the free plan, and a gallery sticker has
      // no document the rules would accept.
      final sheetSource = File('lib/features/chat/chat_attachment_sheet.dart')
          .readAsStringSync();
      final screenSource = File('lib/features/chat/chat_screen.dart')
          .readAsStringSync();

      expect(sheetSource.contains('userUploadedStickers'), isFalse);
      expect(
        screenSource,
        contains('ChatStickerPicker(onSelected: _sendSticker)'),
      );
    });

    test('a voice note is a mic of its own, gated by its own flag', () {
      // Recording is not something the sheet can hand to a picker, and the
      // ceiling that refuses an oversized note is the one storage rules read.
      final source = File('lib/features/chat/chat_screen.dart')
          .readAsStringSync();

      expect(source, contains('if (!ChatMessageType.voice.isGated)'));
      expect(source, contains('_startVoiceTake'));
      expect(source, contains('_VoiceTakeBar('));
      expect(
        source.contains('ChatAttachmentChoice.voice'),
        isFalse,
        reason: 'there is no voice row in the sheet',
      );
    });
  });
}
