import 'package:flutter/material.dart';

/// MixSay's type scale.
///
/// The sizes are the ones the app already paints, so adopting a token never
/// re-flows a line of text. [textTheme] keeps Material 3's own metrics for the
/// roles below and only pins them to these names, which makes this file the one
/// place to retune the scale during the redesign phase.
class AppTypography {
  AppTypography._();

  /// Timestamps and the name under a story ring.
  static const double micro = 11;

  /// Counters and secondary metadata.
  static const double caption = 12;

  /// A field's helper or error line.
  static const double helper = 12.5;

  /// The label inside the "or" divider.
  static const double footnote = 13;

  /// The size most of the app's text paints at.
  static const double body = 14;

  /// Button labels and the text inside a field.
  static const double control = 15;

  /// Card and sheet headings.
  static const double emphasis = 16;

  /// A large sheet title.
  static const double title = 22;

  /// The `MixSay` wordmark in the top bar, painted in Pacifico.
  static const double wordmark = 27;

  /// No colors here on purpose: the widget decides whether a line is primary or
  /// muted, and a color set on a text role would override a button's own
  /// foreground.
  static TextTheme textTheme(TextTheme base) => base.copyWith(
    titleLarge: base.titleLarge?.copyWith(fontSize: title),
    titleMedium: base.titleMedium?.copyWith(fontSize: emphasis),
    titleSmall: base.titleSmall?.copyWith(fontSize: body),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: emphasis),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: body),
    bodySmall: base.bodySmall?.copyWith(fontSize: caption),
    labelLarge: base.labelLarge?.copyWith(fontSize: body),
    labelMedium: base.labelMedium?.copyWith(fontSize: caption),
    labelSmall: base.labelSmall?.copyWith(fontSize: micro),
  );

  static TextStyle get button =>
      const TextStyle(fontSize: control, fontWeight: FontWeight.w600);
}
