import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/home/presentation/widgets/stories_bar.dart';
import 'package:social_chat/features/home/presentation/widgets/story_viewer.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';
import 'package:social_chat/features/stories/presentation/seen_stories_provider.dart';
import 'package:social_chat/features/stories/presentation/story_providers.dart';

class _FakePicker extends ImagePickerPlatform {
  int picks = 0;
  final Completer<XFile?> gate = Completer<XFile?>();

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    picks++;
    return gate.future;
  }
}

class _FakeStoryRepository implements StoryRepository {
  _FakeStoryRepository(this.groups);

  final List<StoryGroup> groups;

  @override
  Stream<List<StoryGroup>> watchActiveStoryGroups() => Stream.value(groups);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Story _story(String id, String authorId, String username) => Story(
  id: id,
  authorId: authorId,
  username: username,
  fullName: username,
  mediaUrl: 'https://cdn.test/$id.jpg',
  createdAt: DateTime.now(),
);

StoryGroup _group(String authorId, String username, int count) => StoryGroup(
  authorId: authorId,
  stories: [
    for (var index = 0; index < count; index++)
      _story('$authorId-$index', authorId, username),
  ],
);

Widget _harness(List<StoryGroup> groups) => ProviderScope(
  overrides: [
    storyRepositoryProvider.overrideWith((ref) => _FakeStoryRepository(groups)),
    currentUserIdProvider.overrideWithValue('me'),
    currentProfileProvider.overrideWith(
      (ref) async =>
          const AppUser(id: 'me', username: 'mixsay.me', fullName: 'MixSay Me'),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: const Scaffold(body: StoriesBar()),
  ),
);

/// The ring each rail circle wears, in the order the rail shows them.
List<AvatarStory> _rings(WidgetTester tester) => tester
    .widgetList<UserAvatar>(find.byType(UserAvatar))
    .map((avatar) => avatar.story)
    .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an author has a coloured ring until their stories open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([_group('layla', 'layla.h', 2), _group('nur', 'nur.k', 1)]),
    );
    await tester.pumpAndSettle();

    // The first circle is the signed-in user, who has no story of their own.
    expect(_rings(tester), [
      AvatarStory.seen,
      AvatarStory.unseen,
      AvatarStory.unseen,
    ]);

    await tester.tap(find.text('layla.h'));
    await tester.pump();
    expect(_rings(tester), [
      AvatarStory.seen,
      AvatarStory.seen,
      AvatarStory.unseen,
    ]);

    // Only the route transition is pumped. Settling to idle would let the
    // viewer's 4-second-per-story ticker run the whole set and close itself.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StoryViewerPage), findsOneWidget);

    // Leave the viewer so its ticker does not outlive the test.
    Navigator.of(tester.element(find.byType(StoryViewerPage))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ring that was opened last time starts grey', (tester) async {
    SharedPreferences.setMockInitialValues({
      'seen_story_groups_me': ['layla'],
    });
    await tester.pumpWidget(
      _harness([_group('layla', 'layla.h', 1), _group('nur', 'nur.k', 1)]),
    );
    await tester.pumpAndSettle();

    expect(_rings(tester), [
      AvatarStory.seen,
      AvatarStory.seen,
      AvatarStory.unseen,
    ]);
  });

  testWidgets('own stories get one rail circle, not two', (tester) async {
    await tester.pumpWidget(
      _harness([_group('layla', 'layla.h', 1), _group('me', 'mixsay.me', 2)]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UserAvatar), findsNWidgets(2));
    expect(find.text('Your story'), findsOneWidget);
    expect(find.text('layla.h'), findsOneWidget);
    // Opening my own story is not "seen": the ring stays the brand sweep.
    expect(_rings(tester), [AvatarStory.unseen, AvatarStory.unseen]);
  });

  testWidgets('a second tap while the picker is open does not pick again', (
    tester,
  ) async {
    final picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Your story'));
    await tester.pump();
    await tester.tap(find.text('Your story'));
    await tester.pump();

    expect(picker.picks, 1);
    // The busy circle replaces the tappable ring while the upload runs.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    picker.gate.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('seen stories are stored per account', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(SeenStoriesController.keyFor('me'), 'seen_story_groups_me');
    expect(SeenStoriesController.keyFor('you'), 'seen_story_groups_you');
    expect(prefs.getString(SeenStoriesController.keyFor('me')), isNull);
  });
}
