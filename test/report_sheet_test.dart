import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/reports/data/report_repository.dart';
import 'package:social_chat/features/reports/presentation/report_providers.dart';
import 'package:social_chat/features/reports/presentation/report_sheet.dart';

/// Stands in for Firestore so the sheet's choices can be checked without a
/// Firebase app: it records what the repository would have written.
class _RecordingReports implements ReportRepository {
  final List<ReportReason> reasons = [];
  final List<String?> notes = [];
  bool shouldFail = false;

  @override
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? extraNote,
  }) async {
    reasons.add(reason);
    notes.add(ReportRepository.normalizeNote(extraNote));
    if (shouldFail) throw Exception('permission denied');
  }
}

Widget _harness(
  Locale locale,
  ReportRepository repository, {
  ReportTarget target = ReportTarget.post,
}) => ProviderScope(
  overrides: [reportRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showReportSheet(context, target: target, targetId: 'post-1'),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  /// The sheet is taller than the 800x600 test surface, so the send button
  /// would sit off-screen and refuse taps.
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the sheet offers exactly the six reasons the rules allow', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(_harness(const Locale('en'), _RecordingReports()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final label in [
      'Spam',
      'Harassment or bullying',
      'Nudity or sexual content',
      'Violence',
      'False information',
      'Something else',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('sending needs a reason and writes the chosen one', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final reports = _RecordingReports();
    await tester.pumpWidget(_harness(const Locale('en'), reports));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final send = find.widgetWithText(FilledButton, 'Send report');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.tap(find.text('Violence'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);

    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(reports.reasons, [ReportReason.violence]);
    // The sheet hands over the raw field; the repository drops a blank note
    // before it reaches Firestore.
    expect(reports.notes.single, isNull);
    expect(find.text('Report sent'), findsOneWidget);
    expect(find.text('Violence'), findsNothing);
  });

  testWidgets('a note is sent with the report', (tester) async {
    usePhoneSurface(tester);
    final reports = _RecordingReports();
    await tester.pumpWidget(_harness(const Locale('en'), reports));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  targeted me first  ');
    await tester.tap(find.text('Harassment or bullying'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();

    expect(reports.notes, ['targeted me first']);
  });

  testWidgets('a failed send keeps the sheet open and says so', (tester) async {
    usePhoneSurface(tester);
    final reports = _RecordingReports()..shouldFail = true;
    await tester.pumpWidget(_harness(const Locale('en'), reports));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle();

    expect(find.text('Could not complete, try again'), findsOneWidget);
    expect(find.text('Spam'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Arabic sheet is readable at a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness(
        const Locale('ar'),
        _RecordingReports(),
        target: ReportTarget.story,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('الإبلاغ عن القصة'), findsOneWidget);
    expect(find.text('رسائل مزعجة'), findsOneWidget);
    expect(find.text('إرسال البلاغ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
