import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/loading_skeleton.dart';

Widget _harness(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

final _blocks = find.descendant(
  of: find.byType(LoadingSkeleton),
  matching: find.byType(Container),
);

/// The localizations load in a frame of their own, so the skeleton is only on
/// screen after a settled pump.
Future<void> _show(
  WidgetTester tester,
  Widget child, {
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(_harness(child, direction: direction));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the skeleton settles instead of shimmering forever', (
    tester,
  ) async {
    await _show(tester, const LoadingSkeleton());

    // pumpAndSettle inside _show only returns when no animation is left running,
    // which is the whole reason this skeleton paints a still frame.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the row paints the face block plus one bar per line', (
    tester,
  ) async {
    await _show(tester, const LoadingSkeleton(lines: 3));

    expect(_blocks, findsNWidgets(4));
  });

  testWidgets('without the face block only the lines are painted', (
    tester,
  ) async {
    await _show(tester, const LoadingSkeleton(lines: 2, avatar: false));

    expect(_blocks, findsNWidgets(2));
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('the face block starts the row in $direction', (tester) async {
      await _show(tester, const LoadingSkeleton(), direction: direction);

      final face = tester.getRect(_blocks.first);
      final lastBar = tester.getRect(_blocks.last);
      // The face is always the first thing on the reading side: physical left in
      // LTR, physical right in RTL.
      expect(
        direction == TextDirection.ltr
            ? face.left < lastBar.left
            : face.right > lastBar.right,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a narrow screen at a large text scale still fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _show(
      tester,
      const LoadingSkeleton(lines: 4),
      direction: TextDirection.rtl,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a screen reader is told the content is loading', (tester) async {
    final handle = tester.ensureSemantics();
    await _show(tester, const LoadingSkeleton());

    expect(
      tester.getSemantics(find.byType(LoadingSkeleton)).label,
      contains('Loading'),
    );
    handle.dispose();
  });
}
