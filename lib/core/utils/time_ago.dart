/// Short relative time like Instagram: now / 5m / 3h / 2d / 1w / 3mo / 1y.
String timeAgo(DateTime dateTime, {required bool isArabic}) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.isNegative || difference.inSeconds < 60) {
    return isArabic ? 'الآن' : 'now';
  }
  final minutes = difference.inMinutes;
  if (minutes < 60) return isArabic ? '$minutes د' : '${minutes}m';
  final hours = difference.inHours;
  if (hours < 24) return isArabic ? '$hours س' : '${hours}h';
  final days = difference.inDays;
  if (days < 7) return isArabic ? '$days يوم' : '${days}d';
  if (days < 30) {
    final weeks = days ~/ 7;
    return isArabic ? '$weeks أسبوع' : '${weeks}w';
  }
  if (days < 365) {
    final months = days ~/ 30;
    return isArabic ? '$months شهر' : '${months}mo';
  }
  final years = days ~/ 365;
  return isArabic ? '$years سنة' : '${years}y';
}
