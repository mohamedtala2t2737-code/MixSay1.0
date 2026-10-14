import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/widgets/user_avatar.dart';

Widget _harness(
  AvatarStory story, {
  bool busy = false,
  bool showPlus = false,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: UserAvatar(
        name: 'Salma',
        radius: 26,
        story: story,
        busy: busy,
        showPlus: showPlus,
      ),
    ),
  ),
);

void main() {
  testWidgets('a plain avatar is the circle itself, with no ring', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(AvatarStory.none));

    expect(tester.getSize(find.byType(UserAvatar)), const Size(52, 52));
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final face in <(AvatarStory, double)>[
    (AvatarStory.unseen, 56),
    (AvatarStory.seen, 58),
  ]) {
    testWidgets('the ${face.$1} ring keeps the rail tile the same box', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(face.$1));

      // 26 radius, a 3 band and two 2 gaps: the box the stories rail drew
      // before this widget owned the ring. The sweep is a pixel thicker, so the
      // face it leaves is a pixel smaller on each side — exactly what the rail
      // already painted.
      expect(tester.getSize(find.byType(UserAvatar)), const Size(66, 66));
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(
        tester.getSize(find.byType(CircleAvatar)),
        Size(face.$2, face.$2),
        reason: 'the face fills the box the ring leaves it',
      );
    });
  }

  testWidgets('seen and unseen swap color, not size', (tester) async {
    await tester.pumpWidget(_harness(AvatarStory.unseen));
    final unseen = tester.getSize(find.byType(UserAvatar));
    await tester.pumpWidget(_harness(AvatarStory.seen));
    expect(tester.getSize(find.byType(UserAvatar)), unseen);
  });

  testWidgets(
    'uploading spins over the ring and the badge sits in the corner',
    (tester) async {
      await tester.pumpWidget(
        _harness(AvatarStory.seen, busy: true, showPlus: true),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    },
  );

  testWidgets('a plain avatar has no ring to overlay, so it paints neither',
      (tester) async {
    await tester.pumpWidget(
      _harness(AvatarStory.none, busy: true, showPlus: true),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('the ring paints the same box in $direction', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: UserAvatar(
                  name: 'Salma',
                  radius: 26,
                  story: AvatarStory.unseen,
                  showPlus: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(UserAvatar)), const Size(66, 66));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initials fall back to the person icon without a name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: UserAvatar(name: '  ', radius: 26)),
        ),
      ),
    );

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.text('S'), findsNothing);
  });

  testWidgets('a long name at a large text scale does not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserAvatar(
              name: 'Mohamed Abdel-Rahman',
              radius: 26,
              story: AvatarStory.unseen,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(UserAvatar)), const Size(66, 66));
  });
}
