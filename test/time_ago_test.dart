import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/utils/time_ago.dart';

void main() {
  DateTime ago(Duration duration) => DateTime.now().subtract(duration);

  test('just now', () {
    expect(timeAgo(ago(const Duration(seconds: 10)), isArabic: false), 'now');
    expect(timeAgo(ago(const Duration(seconds: 10)), isArabic: true), 'الآن');
  });

  test('minutes', () {
    expect(timeAgo(ago(const Duration(minutes: 5)), isArabic: false), '5m');
    expect(timeAgo(ago(const Duration(minutes: 5)), isArabic: true), '5 د');
  });

  test('hours', () {
    expect(timeAgo(ago(const Duration(hours: 3)), isArabic: false), '3h');
    expect(timeAgo(ago(const Duration(hours: 3)), isArabic: true), '3 س');
  });

  test('days', () {
    expect(timeAgo(ago(const Duration(days: 2)), isArabic: false), '2d');
    expect(timeAgo(ago(const Duration(days: 2)), isArabic: true), '2 يوم');
  });

  test('weeks', () {
    expect(timeAgo(ago(const Duration(days: 14)), isArabic: false), '2w');
    expect(timeAgo(ago(const Duration(days: 14)), isArabic: true), '2 أسبوع');
  });

  test('months and years', () {
    expect(timeAgo(ago(const Duration(days: 90)), isArabic: false), '3mo');
    expect(timeAgo(ago(const Duration(days: 730)), isArabic: false), '2y');
    expect(timeAgo(ago(const Duration(days: 730)), isArabic: true), '2 سنة');
  });
}
