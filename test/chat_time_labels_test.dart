import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_time_labels.dart';

void main() {
  final arabic = const AppStrings(Locale('ar'));
  final english = const AppStrings(Locale('en'));
  final now = DateTime(2026, 10, 15, 18, 45);

  group('same day', () {
    test('two times in one local day are the same day', () {
      expect(
        chatIsSameDay(
          DateTime(2026, 10, 15, 0, 1),
          DateTime(2026, 10, 15, 23, 59),
        ),
        isTrue,
      );
    });

    test('across midnight they are not', () {
      expect(
        chatIsSameDay(
          DateTime(2026, 10, 15, 23, 59),
          DateTime(2026, 10, 16, 0, 1),
        ),
        isFalse,
      );
    });
  });

  group('clock', () {
    test('pads the hour and the minute', () {
      expect(chatTimeLabel(english, DateTime(2026, 10, 15, 9, 5)), '09:05');
    });

    test('uses Arabic-Indic digits when the app speaks Arabic', () {
      expect(chatTimeLabel(arabic, DateTime(2026, 10, 15, 9, 5)), '٠٩:٠٥');
    });
  });

  group('date separator', () {
    test('today is a word, not a number', () {
      expect(
        chatDateLabel(english, DateTime(2026, 10, 15, 2), now: now),
        'Today',
      );
      expect(
        chatDateLabel(arabic, DateTime(2026, 10, 15, 2), now: now),
        'النهاردة',
      );
    });

    test('yesterday is a word too', () {
      expect(
        chatDateLabel(english, DateTime(2026, 10, 14, 23, 59), now: now),
        'Yesterday',
      );
      expect(
        chatDateLabel(arabic, DateTime(2026, 10, 14, 23, 59), now: now),
        'أمس',
      );
    });

    test('anything older is a date', () {
      expect(
        chatDateLabel(english, DateTime(2026, 9, 1, 8), now: now),
        '01/09/2026',
      );
      expect(
        chatDateLabel(arabic, DateTime(2026, 9, 1, 8), now: now),
        '٠١/٠٩/٢٠٢٦',
      );
    });

    test('yesterday across a month boundary still reads yesterday', () {
      expect(
        chatDateLabel(
          english,
          DateTime(2026, 9, 30, 20),
          now: DateTime(2026, 10, 1, 6),
        ),
        'Yesterday',
      );
    });

    test('a year older is never a word', () {
      expect(
        chatDateLabel(english, DateTime(2025, 10, 15, 12), now: now),
        '15/10/2025',
      );
    });
  });
}
