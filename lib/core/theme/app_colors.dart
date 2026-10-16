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

  /// The chat thread's own greens and grays. A thread is scanned by side, not
  /// by reading, so what I sent is green and what they sent is neutral gray
  /// even though the rest of the app keeps [brandPurple].
  static const chatOutgoingOnDark = Color(0xFF0E3B2E);
  static const chatIncomingOnDark = Color(0xFF23262B);
  static const chatOutgoingOnLight = Color(0xFFD7F0E1);
  static const chatIncomingOnLight = Color(0xFFFFFFFF);

  /// The round send / mic button beside the composer.
  static const chatActionGreen = Color(0xFF159F5A);

  /// Behind the thread, and behind the app bar of the chat screen only.
  static const chatWallpaperDark = Color(0xFF0A1410);
  static const chatWallpaperLight = Color(0xFFEFF3EE);
  static const chatAppBarDark = Color(0xFF141B18);

  static Color chatBubble(bool outgoing, Brightness brightness) {
    if (brightness == Brightness.light) {
      return outgoing ? chatOutgoingOnLight : chatIncomingOnLight;
    }
    return outgoing ? chatOutgoingOnDark : chatIncomingOnDark;
  }

  /// Text inside a bubble. The light theme's bubbles are pale, so it goes dark
  /// there and stays white over the dark green and gray.
  static Color chatBubbleText(Brightness brightness) =>
      brightness == Brightness.light ? textOnLight : textOnDark;

  static Color chatWallpaper(Brightness brightness) =>
      brightness == Brightness.light ? chatWallpaperLight : chatWallpaperDark;

  /// The chat app bar keeps the dark look in both themes, which is what makes
  /// the thread readable straight away.
  static Color chatAppBar(Brightness brightness) =>
      brightness == Brightness.light ? chatOutgoingOnDark : chatAppBarDark;

  /// The name and the bar of a quoted message. The pale light-theme bubbles take
  /// the button green; over the dark green bubble that same green is too close
  /// to the background to see, so the dark theme gets its lighter sibling.
  static const chatQuoteGreenOnDark = Color(0xFF7BD8A8);

  static Color chatQuoteAccent(Brightness brightness) =>
      brightness == Brightness.light ? chatActionGreen : chatQuoteGreenOnDark;

  /// A small rounded chip that sits on the thread itself: a date separator, or
  /// the time over a sticker.
  static Color chatChip(Brightness brightness) =>
      brightness == Brightness.light ? Color(0xFFDDE5DE) : Color(0xFF1B2A24);

  static Color chatChipText(Brightness brightness) =>
      brightness == Brightness.light ? textOnLight : textMutedOnDark;

  /// The blue a read receipt turns. The brand blue is bright enough over the
  /// dark green bubble but nearly disappears on the pale light-theme one, so
  /// that theme gets the deeper shade of the same blue.
  static const chatReadBlueOnLight = Color(0xFF0A84C7);

  static Color chatTickRead(Brightness brightness) =>
      brightness == Brightness.light ? chatReadBlueOnLight : brandBlue;
}
