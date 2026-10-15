import 'package:social_chat/core/l10n/app_strings.dart';

bool chatIsSameDay(DateTime first, DateTime second) {
  final a = first.toLocal();
  final b = second.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The clock under a bubble, with the locale's digits.
String chatTimeLabel(AppStrings strings, DateTime time) {
  final local = time.toLocal();
  return strings.number(
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}',
  );
}

/// The separator above the first message of a day. Today and Yesterday are
/// words, anything older is a plain date, so a long thread stays scannable.
String chatDateLabel(AppStrings strings, DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (chatIsSameDay(local, today)) return strings.today;
  if (chatIsSameDay(
    local,
    DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1)),
  )) {
    return strings.yesterday;
  }
  return strings.number(
    '${local.day.toString().padLeft(2, '0')}/'
    '${local.month.toString().padLeft(2, '0')}/'
    '${local.year}',
  );
}
