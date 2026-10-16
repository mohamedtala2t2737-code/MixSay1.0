import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/core/theme/app_typography.dart';

void main() {
  for (final (label, theme) in <(String, ThemeData)>[
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('the pinned type scale keeps the platform default ($label)', (
      tester,
    ) async {
      late ThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              resolved = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.textTheme.bodyMedium?.fontSize, AppTypography.body);
      expect(resolved.textTheme.titleMedium?.fontSize, AppTypography.emphasis);
      expect(resolved.textTheme.labelSmall?.fontSize, AppTypography.micro);

      // The roles MixSay does not pin have to survive, otherwise this scale
      // would have replaced the whole default text theme.
      expect(resolved.textTheme.displayLarge, isNotNull);
      expect(resolved.textTheme.headlineSmall, isNotNull);
      expect(resolved.textTheme.bodyLarge?.letterSpacing, isNotNull);
    });

    test('$label keeps the MixSay brand and the stock text colors', () {
      // The stock theme is the reference: if pinning sizes had dropped the
      // colors, every label in the app would repaint.
      final stock = ThemeData(brightness: theme.brightness);
      expect(theme.colorScheme.primary, AppColors.brandPurple);
      expect(
        theme.textTheme.bodyMedium?.color,
        stock.textTheme.bodyMedium?.color,
      );
      expect(
        theme.textTheme.titleMedium?.color,
        stock.textTheme.titleMedium?.color,
      );
    });
  }

  test('dark and light paint their own surfaces', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.darkBackground);
    expect(AppTheme.light.scaffoldBackgroundColor, AppColors.lightBackground);
    expect(
      AppColors.fieldFill(Brightness.dark),
      isNot(AppColors.fieldFill(Brightness.light)),
    );
  });
}
