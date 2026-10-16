import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_emoji_picker.dart';
import 'package:social_chat/features/chat/chat_screen.dart';

void main() {
  group('inserting at the caret', () {
    test('a caret in the middle keeps what the user already typed', () {
      final result = insertIntoMessageField(
        text: 'sabah el khir',
        selection: const TextSelection.collapsed(offset: 5),
        insert: ' 😍',
      );
      expect(result.text, 'sabah 😍 el khir');
      expect(result.selection.isCollapsed, isTrue);
      // The space and the surrogate pair together move the caret three units.
      expect(result.selection.start, 8);
    });

    test('a selection is replaced, not widened', () {
      final result = insertIntoMessageField(
        text: 'habibi',
        selection: const TextSelection(baseOffset: 0, extentOffset: 4),
        insert: 'ya',
      );
      expect(result.text, 'yabi');
      expect(result.selection.start, 2);
    });

    test('an untouched field takes the text at its end', () {
      final result = insertIntoMessageField(
        text: 'mixed',
        selection: const TextSelection(baseOffset: -1, extentOffset: -1),
        insert: '!',
      );
      expect(result.text, 'mixed!');
      expect(result.selection.start, 6);
    });

    test('an emoji counts as the code units it really occupies', () {
      // '👍' is a surrogate pair, so the caret has to jump two units.
      final result = insertIntoMessageField(
        text: 'ok ',
        selection: const TextSelection.collapsed(offset: 3),
        insert: '👍',
      );
      expect(result.text, 'ok 👍');
      expect(result.selection.start, 5);
    });
  });

  group('emoji picker', () {
    testWidgets('tapping a face hands it to the message field', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(bottomSheet: ChatEmojiPicker(onSelected: picked.add)),
        ),
      );
      // The delegates resolve asynchronously, so the first frame is still dry.
      await tester.pump();

      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();
      expect(picked, ['😀']);
    });

    testWidgets('the tray is a scrollable grid, not a wall of buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(bottomSheet: ChatEmojiPicker(onSelected: (_) {})),
        ),
      );
      await tester.pump();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Emoji'), findsOneWidget);
    });
  });
}
