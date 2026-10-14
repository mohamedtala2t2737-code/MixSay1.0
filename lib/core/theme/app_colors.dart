import 'package:flutter/material.dart';

/// The single source of truth for MixSay colors: black/white surfaces plus one
/// brand sweep (cyan -> yellow -> pink -> purple). Every screen reads from here.
class AppColors {
  AppColors._();

  static const brandBlue = Color(0xFF38B6FF);
  static const brandYellow = Color(0xFFFFC244);
  static const brandPink = Color(0xFFFF3366);
  static const brandPurple = Color(0xFF6200EA);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandBlue, brandYellow, brandPink, brandPurple],
    stops: [0.0, 0.35, 0.70, 1.0],
  );

  /// Text painted on top of the sweep: near-black stays legible over the cyan
  /// and yellow stops, which white would not.
  static const onBrandGradient = Color(0xFF0B0B10);

  static const success = Color(0xFF2FB56C);
  static const error = Color(0xFFFF4D5E);

  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1C1C24);
  static const darkSurfaceHigh = Color(0xFF262630);

  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF4F5F9);
  static const lightSurfaceHigh = Color(0xFFE9EBF3);

  static const textOnLight = Color(0xFF0B0B10);
  static const textMutedOnLight = Color(0xFF6B7280);
  static const textOnDark = Color(0xFFFFFFFF);
  static const textMutedOnDark = Color(0xFFA1A1AA);

  static const borderOnLight = Color(0xFFDADCE5);
  static const borderOnDark = Color(0xFF2A2A35);

  static Color fieldFill(Brightness brightness) =>
      brightness == Brightness.light ? lightSurface : darkSurface;
}
