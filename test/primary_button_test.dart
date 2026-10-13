import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/widgets/primary_button.dart';

void main() {
  testWidgets('shows the label and fires onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'دخول', onPressed: () => pressed = true),
        ),
      ),
    );

    expect(find.text('دخول'), findsOneWidget);

    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();

    expect(pressed, isTrue);
  });

  testWidgets('shows a spinner and ignores taps while loading',
      (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(
            label: 'دخول',
            loading: true,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('دخول'), findsNothing);
    expect(pressed, isFalse);
  });
}
