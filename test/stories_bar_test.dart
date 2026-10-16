import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
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
  _FakeStoryRepository(
    this.groups, {
    this.viewers = const [],
    this.viewFailure,
  });

  final List<StoryGroup> groups;
  final List<StoryViewer> viewers;

  /// The error the audience write should throw, to prove a failed view record
  /// never stops the player.
  final Object? viewFailure;

  final List<String> viewed = [];

  @override
  Stream<List<StoryGroup>> watchActiveStoryGroups() => Stream.value(groups);

  @override
  Future<void> markViewed(Story story) async {
    viewed.add(story.id);
    if (viewFailure != null) throw viewFailure!;
  }

  @override
  Future<List<StoryViewer>> viewersOf(String storyId) async => viewers;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeChatRepository implements ChatRepository {
  final List<String> sent = [];

  @override
  String createClientId() => 'client-1';

  @override
  Future<String> getOrCreateConversation(String otherUserId) async =>
      'conversation-$otherUserId';

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientId,
    ChatReply? replyTo,
    bool forwarded = false,
  }) async {
    sent.add('$conversationId:$text');
    return ChatMessage(
      id: 'm1',
      conversationId: conversationId,
      senderId: 'me',
      content: text,
      clientId: clientId,
      createdAt: DateTime.now(),
      status: 'sent',
    );
  }

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

/// Opens the viewer through a real route so the close gestures can pop it, the
/// way the rail does.
class _ViewerHost extends StatelessWidget {
  const _ViewerHost({required this.group, required this.currentUserId});

  final StoryGroup group;
  final String currentUserId;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => StoryViewerPage(
              groups: [group],
              initialIndex: 0,
              currentUserId: currentUserId,
            ),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<_FakeStoryRepository> _openViewer(
  WidgetTester tester, {
  required StoryGroup group,
  String currentUserId = 'me',
  List<StoryViewer> viewers = const [],
  Object? viewFailure,
  ChatRepository? chat,
}) async {
  final stories = _FakeStoryRepository(
    [group],
    viewers: viewers,
    viewFailure: viewFailure,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storyRepositoryProvider.overrideWith((ref) => stories),
        if (chat != null) chatRepositoryProvider.overrideWithValue(chat),
        currentUserIdProvider.overrideWithValue(currentUserId),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: _ViewerHost(group: group, currentUserId: currentUserId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(StoryViewerPage), findsOneWidget);
  return stories;
}

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

  testWidgets('the viewer records each story it shows', (tester) async {
    final stories = await _openViewer(
      tester,
      group: _group('layla', 'layla.h', 2),
    );

    expect(stories.viewed, ['layla-0']);

    // Forward with a tap on the trailing side, back with a tap on the leading
    // one, and each stop is a new audience entry.
    await tester.tapAt(
      tester.getCenter(find.byType(CachedNetworkImage)) + const Offset(150, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(stories.viewed, ['layla-0', 'layla-1']);

    await tester.tapAt(
      tester.getCenter(find.byType(CachedNetworkImage)) - const Offset(150, 0),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(stories.viewed, ['layla-0', 'layla-1', 'layla-0']);

    Navigator.of(tester.element(find.byType(StoryViewerPage))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a view the database refuses never stops the player', (
    tester,
  ) async {
    await _openViewer(
      tester,
      group: _group('layla', 'layla.h', 1),
      viewFailure: StateError('Sign in to view stories'),
    );

    expect(find.byType(StoryViewerPage), findsOneWidget);
    expect(find.text('layla.h'), findsOneWidget);

    Navigator.of(tester.element(find.byType(StoryViewerPage))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reply becomes a chat message to the author', (tester) async {
    final chat = _FakeChatRepository();
    await _openViewer(tester, group: _group('layla', 'layla.h', 1), chat: chat);

    await tester.enterText(find.byType(TextField), 'salam!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();

    expect(chat.sent, ['conversation-layla:salam!']);
    // The app-level messenger paints the bar on every Scaffold under it, so the
    // route below the viewer shows the same copy.
    expect(find.text('Reply sent'), findsWidgets);
    // The box empties so the next story does not resend the same reply.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('my own story has no reply box but shows its audience', (
    tester,
  ) async {
    await _openViewer(
      tester,
      group: _group('me', 'mixsay.me', 1),
      viewers: const [
        StoryViewer(
          userId: 'layla',
          username: 'layla.h',
          fullName: 'Layla H',
          viewedAt: null,
        ),
      ],
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Viewers'), findsOneWidget);
    expect(find.text('layla.h'), findsOneWidget);
    expect(find.text('Nobody has seen this yet'), findsNothing);
  });

  testWidgets('an audience that is still empty says so', (tester) async {
    await _openViewer(tester, group: _group('me', 'mixsay.me', 1));

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nobody has seen this yet'), findsOneWidget);
  });

  testWidgets('dragging the story down closes it', (tester) async {
    await _openViewer(tester, group: _group('layla', 'layla.h', 2));

    final center = tester.getCenter(find.byType(CachedNetworkImage));

    await tester.dragFrom(center, const Offset(0, 60));
    await tester.pump();
    // Not far enough yet: the picture springs back and the viewer stays.
    expect(find.byType(StoryViewerPage), findsOneWidget);

    await tester.dragFrom(center, const Offset(0, 220));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(StoryViewerPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
