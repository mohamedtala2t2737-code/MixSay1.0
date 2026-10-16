import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/confirmation_dialog.dart';

bool? _result;

Widget _harness(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppStrings.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final s = AppStrings.of(context);
            _result = await askConfirmation(
              context,
              title: s.deletePost,
              message: s.deletePostConfirm,
              confirmLabel: s.deletePost,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

/// The localizations load in a frame of their own, so every test needs a settled
/// pump before it can see the button that opens the dialog.
Future<void> _open(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(_harness(locale));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _result = null);

  testWidgets('the confirm answer comes back as true', (tester) async {
    await _open(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete post'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(_result, isTrue);
  });

  testWidgets('cancel answers false without touching the action', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(_result, isFalse);
  });

  testWidgets('backing out through the scrim also answers false', (
    tester,
  ) async {
    await _open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(_result, isFalse);
  });

  testWidgets('the dialog reads in Arabic at a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _open(tester, locale: const Locale('ar'));

    expect(find.text('حذف المنشور'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'حذف المنشور'));
    await tester.pumpAndSettle();
    expect(_result, isTrue);
  });
}
