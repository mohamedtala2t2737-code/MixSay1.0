import 'package:flutter/widgets.dart';

/// MixSay's spacing scale. Every value is a gap the app already paints, so
/// adopting a token here never moves a layout; screens still carrying their own
/// numbers pick these up during the redesign phase.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// The largest gap in the app: the padding around empty, error and loading
  /// states, which need room to breathe on their own.
  static const double block = 32;

  /// The horizontal gutter every card, sheet and screen uses.
  static const double gutter = 14;

  static const EdgeInsets gutterHorizontal = EdgeInsets.symmetric(
    horizontal: gutter,
  );

  /// Inside a text field: 14 across, 16 down.
  static const EdgeInsets field = EdgeInsets.symmetric(
    horizontal: gutter,
    vertical: lg,
  );

  /// Inside a row: the gutter across and a small vertical rhythm.
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: gutter,
    vertical: sm,
  );
}
