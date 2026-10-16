import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_wallpaper.dart';

/// The chat screen cannot be pumped without Firebase, so what a test can hold
/// this restyle to is the palette it paints with, the wallpaper it puts behind
/// the thread, and that no control appears on screen without something behind
/// it.
///
/// Checked out sources carry CRLF on Windows, so the file is read as one line
/// ending.
final _screenSource = File('lib/features/chat/chat_screen.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

double _lightness(Color color) => HSLColor.fromColor(color).lightness;

void main() {
  group('the palette', () {
    test('a bubble is darker or paler than its text in both themes', () {
      for (final brightness in Brightness.values) {
        for (final outgoing in [true, false]) {
          final contrast =
              (_lightness(AppColors.chatBubble(outgoing, brightness)) -
                      _lightness(AppColors.chatBubbleText(brightness)))
                  .abs();
          expect(
            contrast,
            greaterThan(0.35),
            reason:
                '$outgoing/$brightness bubble and text sit too close to read',
          );
        }
      }
    });

    test('the dark thread is a dark wallpaper and the light one is pale', () {
      expect(
        _lightness(AppColors.chatWallpaper(Brightness.dark)),
        lessThan(0.25),
      );
      expect(
        _lightness(AppColors.chatWallpaper(Brightness.light)),
        greaterThan(0.75),
      );
    });

    test('what I sent reads green, whatever the theme', () {
      for (final brightness in Brightness.values) {
        final hue = HSLColor.fromColor(AppColors.chatBubble(true, brightness))
            .hue;
        expect(
          hue,
          inInclusiveRange(90, 190),
          reason: '$brightness outgoing bubble is not in the green family',
        );
      }
    });

    test('their side is neutral, not a second brand colour', () {
      for (final brightness in Brightness.values) {
        final color = HSLColor.fromColor(
          AppColors.chatBubble(false, brightness),
        );
        expect(
          color.saturation,
          lessThan(0.2),
          reason: '$brightness incoming bubble drifted toward a hue',
        );
      }
    });

    test('calls stay off until Phase 4 is confirmed', () {
      expect(ChatFeatures.calls, isFalse);
    });
  });

  group('the wallpaper', () {
    Future<void> pumpThread(WidgetTester tester, Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: ChatWallpaper(child: Center(child: Text('thread'))),
          ),
        ),
      );
    }

    testWidgets('it keeps the thread on top of it', (tester) async {
      await pumpThread(tester, Brightness.dark);
      expect(find.text('thread'), findsOneWidget);
    });

    Color baseOf(WidgetTester tester) =>
        (tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: find.byType(ChatWallpaper),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration)
            .color!;

    testWidgets('the dark thread gets the dark base', (tester) async {
      await pumpThread(tester, Brightness.dark);
      expect(baseOf(tester), AppColors.chatWallpaperDark);
    });

    testWidgets('the light thread gets the pale base', (tester) async {
      await pumpThread(tester, Brightness.light);
      expect(baseOf(tester), AppColors.chatWallpaperLight);
    });

    testWidgets('the pattern is painted, not a bitmap that can blur', (
      tester,
    ) async {
      await pumpThread(tester, Brightness.dark);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(
        _wallpaperSource.contains('Image.asset'),
        isFalse,
        reason: 'a wallpaper asset would need one file per brightness',
      );
    });
  });

  group('the app bar', () {
    test('the call icons exist only behind the calls flag', () {
      expect(_screenSource, contains('if (ChatFeatures.calls)'));
      expect(_screenSource, contains('tooltip: s.voiceCall'));
      expect(_screenSource, contains('tooltip: s.videoCall'));
    });

    test('it is the dark bar the thread is read against', () {
      expect(_screenSource, contains('AppColors.chatAppBar('));
      expect(_screenSource, contains('foregroundColor: Colors.white'));
    });

    test('no menu row is a row that does nothing', () {
      final declared = RegExp(r'enum _ChatMenuAction \{([^}]*)\}');
      final match = declared.firstMatch(_screenSource);
      expect(match, isNotNull, reason: 'the menu lost its actions');
      for (final name
          in match!
              .group(1)!
              .split(',')
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)) {
        expect(
          _screenSource,
          contains('case _ChatMenuAction.$name:'),
          reason: '$name has no handler',
        );
      }
    });

    test('the thread sits on the wallpaper, not on a gradient', () {
      expect(_screenSource, contains('body: ChatWallpaper('));
      expect(_screenSource.contains('LinearGradient'), isFalse);
    });
  });
}

final _wallpaperSource = File('lib/features/chat/chat_wallpaper.dart')
    .readAsStringSync();
