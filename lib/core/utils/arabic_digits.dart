/// MixSay's Arabic copy is written with Arabic-Indic digits (٤، ٢٤، ١٣), so any
/// number rendered next to it has to match or the sentence looks half-translated.
String localizeDigits(String value, {required bool isArabic}) {
  if (!isArabic) return value;
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    buffer.writeCharCode(rune >= 0x30 && rune <= 0x39 ? rune + 0x0630 : rune);
  }
  return buffer.toString();
}
