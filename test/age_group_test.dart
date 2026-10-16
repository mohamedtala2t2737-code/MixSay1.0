import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/utils/age_group.dart';

/// A birth date stored the way sign-up stores it: a UTC calendar date with no
/// meaningful time of day.
DateTime birth(int year, {int month = 1, int day = 1}) =>
    DateTime.utc(year, month, day);

void main() {
  group('the wire shape', () {
    test('there are exactly the two groups the rules compute', () {
      expect(AgeGroup.values.map((group) => group.wire).toList(), [
        'teen',
        'adult',
      ]);
    });

    test('only those two spellings read back', () {
      expect(AgeGroup.fromWire('teen'), AgeGroup.teen);
      expect(AgeGroup.fromWire('adult'), AgeGroup.adult);
      expect(AgeGroup.fromWire('TEEN'), isNull);
      expect(AgeGroup.fromWire('child'), isNull);
      expect(AgeGroup.fromWire(''), isNull);
      expect(AgeGroup.fromWire(null), isNull);
      expect(AgeGroup.fromWire(13), isNull);
    });
  });

  group('the thirteen boundary', () {
    test('a thirteenth birthday is a teen', () {
      expect(
        AgeGroup.of(birthDate: birth(2013), now: birth(2026)),
        AgeGroup.teen,
      );
    });

    test('someone younger than thirteen is filed with teens', () {
      // The app refuses sign-ups below thirteen, so this only happens for a
      // damaged date. The safe reading is the group that hides them.
      expect(
        AgeGroup.of(birthDate: birth(2016), now: birth(2026)),
        AgeGroup.teen,
      );
    });
  });

  group('the eighteen boundary', () {
    test('the day before the eighteenth birthday is still a teen', () {
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 10, day: 16),
          now: DateTime.utc(2026, 10, 15),
        ),
        AgeGroup.teen,
      );
    });

    test('the eighteenth birthday itself is an adult', () {
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 10, day: 16),
          now: DateTime.utc(2026, 10, 16),
        ),
        AgeGroup.adult,
      );
    });

    test('a minute past midnight UTC is the next day for the rules', () {
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 10, day: 16),
          now: DateTime.utc(2026, 10, 15, 23, 59),
        ),
        AgeGroup.teen,
      );
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 10, day: 16),
          now: DateTime.utc(2026, 10, 16, 0, 0),
        ),
        AgeGroup.adult,
      );
    });

    test('the time of day on the stored date is ignored', () {
      expect(
        AgeGroup.of(
          birthDate: DateTime.utc(2008, 10, 16, 23, 59),
          now: DateTime.utc(2026, 10, 16, 0, 30),
        ),
        AgeGroup.adult,
      );
    });
  });

  group('a 29 February birthday', () {
    test('matures on 1 March when the target year has no 29 February', () {
      // Born on the leap day of 2008: 2026 has no 29 February, so eighteen is
      // reached on 1 March, exactly as the rules read the same date.
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 2, day: 29),
          now: DateTime.utc(2026, 2, 28),
        ),
        AgeGroup.teen,
      );
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 2, day: 29),
          now: DateTime.utc(2026, 3, 1),
        ),
        AgeGroup.adult,
      );
    });

    test('a leap year that is not the eighteenth changes nothing', () {
      // 2024 does have a 29 February, but it is only the sixteenth year after
      // this birthday, so the extra day is not a boundary.
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 2, day: 29),
          now: DateTime.utc(2024, 2, 29),
        ),
        AgeGroup.teen,
      );
    });

    test('a fourteen-year gap cannot land on a leap day', () {
      // Eighteen is not a multiple of four, so a 29 February birthday never
      // has a 29 February in its eighteenth year; 1 March is always the day.
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 2, day: 29),
          now: DateTime.utc(2026, 3, 2),
        ),
        AgeGroup.adult,
      );
    });

    test('someone born the day before still matures a day earlier', () {
      expect(
        AgeGroup.of(
          birthDate: birth(2008, month: 2, day: 28),
          now: DateTime.utc(2026, 2, 28),
        ),
        AgeGroup.adult,
      );
    });
  });
}
