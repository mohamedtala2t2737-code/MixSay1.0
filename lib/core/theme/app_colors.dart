import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand / chat (WhatsApp-style teal + green)
  static const chatTeal = Color(0xFF008069);
  static const chatGreen = Color(0xFF25D366);
  static const chatAccent = Color(0xFF00A884);

  // Light chat palette
  static const lightChatWallpaper = Color(0xFFEFEAE2);
  static const lightOutgoingBubble = Color(0xFFD9FDD3);
  static const lightIncomingBubble = Color(0xFFFFFFFF);

  // Dark chat palette
  static const darkChatBackground = Color(0xFF0B141A);
  static const darkChatSurface = Color(0xFF202C33);
  static const darkOutgoingBubble = Color(0xFF005C4B);

  // Text
  static const darkText = Color(0xFF111B21);
  static const darkTextMuted = Color(0xFF667781);
  static const lightText = Color(0xFFE9EDEF);
  static const lightTextMuted = Color(0xFF8696A0);

  // Auth screens (Instagram / Facebook style)
  static const authBlue = Color(0xFF0095F6);
  static const facebookBlue = Color(0xFF1877F2);
  static const signupGreen = Color(0xFF237A28);
  static const fieldBorder = Color(0xFFDBDBDB);

  static const error = Color(0xFFED4956);

  // Brand palette (MixSay wordmark: blue -> purple -> orange)
  static const brandBlue = Color(0xFF4F5BD5);
  static const brandPurple = Color(0xFF962FBF);
  static const brandPink = Color(0xFFD62976);
  static const brandOrange = Color(0xFFFA7E1E);
  static const brandCream = Color(0xFFF6F2E9);
  static const brandFieldFill = Colors.white;
  static const brandPlaceholder = Color(0xFF9B968E);

  /// The single source of truth for the brand sweep used by the logo,
  /// the splash screen, gradient input borders and primary buttons.
  static const brandGradient = LinearGradient(
    colors: [brandBlue, brandPurple, brandPink, brandOrange],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
