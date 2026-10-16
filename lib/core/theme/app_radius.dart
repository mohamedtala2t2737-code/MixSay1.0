import 'package:flutter/material.dart';

/// MixSay's corner radii. [field] is deliberately not a round number: it is the
/// radius the text fields already paint, kept exactly so moving to a token does
/// not change a single pixel.
class AppRadius {
  AppRadius._();

  /// Badges and the tiny segments inside the composer preview.
  static const double chip = 4;

  static const double sm = 8;

  /// Buttons, cards and sheet tiles.
  static const double md = 12;

  /// The gradient border around a text field.
  static const double field = 15.6;

  static const double lg = 16;

  static BorderRadius circular(double radius) => BorderRadius.circular(radius);

  static BorderRadius get chipBorder => BorderRadius.circular(chip);
  static BorderRadius get smBorder => BorderRadius.circular(sm);
  static BorderRadius get mdBorder => BorderRadius.circular(md);
  static BorderRadius get fieldBorder => BorderRadius.circular(field);
  static BorderRadius get lgBorder => BorderRadius.circular(lg);
}
