import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/section_header.dart';
import 'package:social_chat/core/widgets/secondary_button.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';

Widget _harness(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('SecondaryButton', () {
    testWidgets('it paints a full width outlined box and reports taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _harness(
          Center(
            child: SecondaryButton(label: 'Try again', onPressed: () => taps++),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SecondaryButton)).height, 48);
      await tester.tap(find.text('Try again'));
      expect(taps, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a pressless button is dimmed and does not fire', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          Center(child: SecondaryButton(label: 'Nope', onPressed: null)),
        ),
      );

      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byType(SecondaryButton),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        0.6,
      );
      await tester.tap(find.text('Nope'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading swaps the label for a spinner and blocks the tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _harness(
          Center(
            child: SecondaryButton(
              label: 'Save',
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.byType(SecondaryButton));
      expect(taps, 0);
    });

    testWidgets('an icon and a long label fit at a large text scale', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _harness(
          Center(
            child: SecondaryButton(
              label: 'Add a video from the gallery on this device',
              icon: Icons.movie_outlined,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });
  });

  group('SectionHeader', () {
    testWidgets('the action sits opposite the title in both directions', (
      tester,
    ) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        await tester.pumpWidget(
          _harness(
            SectionHeader(
              title: 'Friends',
              trailing: TextButton(
                onPressed: () {},
                child: const Text('See all'),
              ),
            ),
            direction: direction,
          ),
        );

        final title = tester.getCenter(find.text('Friends'));
        final action = tester.getCenter(find.text('See all'));
        if (direction == TextDirection.ltr) {
          expect(title.dx, lessThan(action.dx));
        } else {
          expect(title.dx, greaterThan(action.dx));
        }
      }
    });

    testWidgets('a long Arabic label is capped so the action still fits', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _harness(
          SectionHeader(
            title: 'الإعدادات الخاصة بالخصوصية والأمان',
            subtitle: 'تتحكم في مين يشوف منشوراتك',
            trailing: TextButton(onPressed: () {}, child: const Text('الكل')),
          ),
          direction: TextDirection.rtl,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('الكل'), findsOneWidget);
    });
  });

  group('AppListTile', () {
    testWidgets('leading, title, subtitle and trailing all paint', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _harness(
          AppListTile(
            title: 'Salma',
            subtitle: '4 minutes ago',
            leading: const UserAvatar(name: 'Salma', radius: 21),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('4 minutes ago'), findsOneWidget);
      expect(find.byType(UserAvatar), findsOneWidget);
      await tester.tap(find.text('Salma'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('the face leads on the reading side in both directions', (
      tester,
    ) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        await tester.pumpWidget(
          _harness(
            AppListTile(
              title: 'Salma',
              leading: const UserAvatar(name: 'Salma', radius: 21),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            direction: direction,
          ),
        );

        final leading = tester.getCenter(find.byType(UserAvatar)).dx;
        final trailing = tester.getCenter(find.byIcon(Icons.chevron_right)).dx;
        // ListTile mirrors: the face always starts the row on the reading side,
        // which is the physical left in LTR and the physical right in RTL.
        expect(
          leading,
          direction == TextDirection.ltr
              ? lessThan(trailing)
              : greaterThan(trailing),
        );
      }
    });

    testWidgets('a long name and subtitle ellipsize at a large text scale', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _harness(
          AppListTile(
            title: 'Mohamed Abdel-Rahman Mostafa',
            subtitle: 'بعتلك رسالة جديدة في المحادثة دي من دقيقة واحدة',
            leading: const UserAvatar(name: 'M', radius: 21),
            onTap: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
