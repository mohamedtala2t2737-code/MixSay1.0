import 'package:social_chat/core/utils/arabic_digits.dart';

/// Short relative time like Instagram: now / 5m / 3h / 2d / 1w / 3mo / 1y.
String timeAgo(DateTime dateTime, {required bool isArabic}) {
  String count(int value) => localizeDigits('$value', isArabic: isArabic);
  final difference = DateTime.now().difference(dateTime);
  if (difference.isNegative || difference.inSeconds < 60) {
    return isArabic ? 'الآن' : 'now';
  }
  final minutes = difference.inMinutes;
  if (minutes < 60) {
    return isArabic ? '${count(minutes)} د' : '${count(minutes)}m';
  }
  final hours = difference.inHours;
  if (hours < 24) return isArabic ? '${count(hours)} س' : '${count(hours)}h';
  final days = difference.inDays;
  if (days < 7) return isArabic ? '${count(days)} يوم' : '${count(days)}d';
  if (days < 30) {
    final weeks = days ~/ 7;
    return isArabic ? '${count(weeks)} أسبوع' : '${count(weeks)}w';
  }
  if (days < 365) {
    final months = days ~/ 30;
    return isArabic ? '${count(months)} شهر' : '${count(months)}mo';
  }
  final years = days ~/ 365;
  return isArabic ? '${count(years)} سنة' : '${count(years)}y';
}
