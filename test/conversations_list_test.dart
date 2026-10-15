import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/conversations_view.dart';

ChatConversationPreview _chat(
  String name, {
  String? id,
  String? preview,
  DateTime? at,
  int unread = 0,
  ChatMessageType type = ChatMessageType.text,
}) => ChatConversationPreview(
  id: id ?? 'c-$name',
  otherUserId: 'u-$name',
  otherUsername: name.toLowerCase(),
  otherFullName: name,
  lastMessageContent: preview,
  lastMessageAt: at,
  unreadCount: unread,
  lastMessageType: type,
);

/// The repository the list may ask for older pages. Everything else about it
/// is out of this screen's way, so an unfaked call is a loud failure.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository({this.olderPages = const [], this.failToOpen = false});

  final List<List<ChatConversationPreview>> olderPages;
  final bool failToOpen;
  final List<DateTime> askedBefore = [];
  final List<String> opened = [];

  @override
  Future<List<ChatConversationPreview>> fetchOlderConversations({
    String? userId,
    required DateTime before,
  }) async {
    askedBefore.add(before);
    if (olderPages.isEmpty) return const [];
    return olderPages.first;
  }

  @override
  Future<String> getOrCreateConversation(String otherUserId) async {
    opened.add(otherUserId);
    if (failToOpen) throw StateError('profile not found');
    return 'c-$otherUserId';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Widget _harness(
  List<ChatConversationPreview> livePage,
  _FakeChatRepository repository,
) => ProviderScope(
  overrides: [
    chatRepositoryProvider.overrideWithValue(repository),
    conversationsProvider.overrideWith((ref) => Stream.value(livePage)),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: const Scaffold(body: ConversationsListView()),
  ),
);

/// Localizations and the stream both resolve asynchronously, so the list needs
/// a couple of pumps before its rows exist.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump();
}

/// Eight rows are taller than the 600dp test window, which is what makes the
/// list scrollable enough to reach its bottom.
List<ChatConversationPreview> _many() => [
  for (var index = 0; index < 8; index++)
    _chat(
      'Chat $index',
      preview: 'message $index',
      at: DateTime(2026, 10, 15, 12).subtract(Duration(minutes: index)),
    ),
];

void main() {
  group('list rows', () {
    testWidgets('a photo with no caption says Photo', (tester) async {
      await _show(
        tester,
        _harness([
          _chat(
            'Salma',
            preview: '',
            at: DateTime(2026, 10, 15, 9),
            type: ChatMessageType.image,
          ),
        ], _FakeChatRepository()),
      );

      expect(find.text('Photo'), findsOneWidget);
    });

    testWidgets('unread is bold and carries a counter', (tester) async {
      await _show(
        tester,
        _harness([
          _chat(
            'Salma',
            preview: 'ahlan',
            at: DateTime(2026, 10, 15, 9),
            unread: 3,
          ),
        ], _FakeChatRepository()),
      );

      expect(find.text('3'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Salma'));
      expect(title.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('a read conversation is not bold', (tester) async {
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: DateTime(2026, 10, 15, 9)),
        ], _FakeChatRepository()),
      );

      final title = tester.widget<Text>(find.text('Salma'));
      expect(title.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('a brand new chat admits it has no messages yet', (
      tester,
    ) async {
      await _show(tester, _harness([_chat('Salma')], _FakeChatRepository()));

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('yesterday is a word, not a stale clock time', (tester) async {
      final now = DateTime.now();
      await _show(
        tester,
        _harness([
          _chat(
            'Salma',
            preview: 'ahlan',
            at: now.subtract(const Duration(days: 1)),
          ),
        ], _FakeChatRepository()),
      );

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('a chat from earlier today shows the hour', (tester) async {
      final now = DateTime.now();
      // Midnight of today: any fixed hour would fall on yesterday whenever the
      // suite happens to run in the first hours of the morning.
      final today = DateTime(now.year, now.month, now.day);
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: today),
        ], _FakeChatRepository()),
      );

      expect(find.text('Yesterday'), findsNothing);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('searching the list', () {
    testWidgets('a name narrows the rows to that person', (tester) async {
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: DateTime(2026, 10, 15, 9)),
          _chat('Nader', preview: 'ma3a salama', at: DateTime(2026, 10, 15, 8)),
        ], _FakeChatRepository()),
      );

      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump();

      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('Nader'), findsNothing);
    });

    testWidgets('searching asks Firestore for nothing', (tester) async {
      final repository = _FakeChatRepository();
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: DateTime(2026, 10, 15, 9)),
        ], repository),
      );

      await tester.enterText(find.byType(TextField), 'salma');
      await tester.pump();
      expect(repository.askedBefore, isEmpty);
    });

    testWidgets('a name nobody has shows no results', (tester) async {
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: DateTime(2026, 10, 15, 9)),
        ], _FakeChatRepository()),
      );

      await tester.enterText(find.byType(TextField), 'zahra');
      await tester.pump();

      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('the clear button brings the whole list back', (tester) async {
      await _show(
        tester,
        _harness([
          _chat('Salma', preview: 'ahlan', at: DateTime(2026, 10, 15, 9)),
          _chat('Nader', preview: 'ma3a salama', at: DateTime(2026, 10, 15, 8)),
        ], _FakeChatRepository()),
      );

      await tester.enterText(find.byType(TextField), 'salma');
      await tester.pump();
      expect(find.text('Nader'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('Nader'), findsOneWidget);
    });
  });

  group('paging older chats', () {
    testWidgets('reaching the bottom reads the next page once', (tester) async {
      final older = [
        _chat('Salma', preview: 'qadima', at: DateTime(2026, 10, 1, 9)),
      ];
      final repository = _FakeChatRepository(olderPages: [older]);
      await _show(tester, _harness(_many(), repository));

      await tester.fling(find.byType(ListView), const Offset(0, -600), 4000);
      await tester.pump();
      await tester.pump();

      expect(repository.askedBefore.length, 1);
      expect(find.text('Salma'), findsOneWidget);
    });

    testWidgets('a short page is the end, so nothing more is read', (
      tester,
    ) async {
      final repository = _FakeChatRepository(
        olderPages: [
          [_chat('Ola', preview: 'aahir', at: DateTime(2026, 9, 1, 9))],
        ],
      );
      await _show(tester, _harness(_many(), repository));

      await tester.fling(find.byType(ListView), const Offset(0, -600), 4000);
      await tester.pump();
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, -600), 4000);
      await tester.pump();
      await tester.pump();

      expect(repository.askedBefore.length, 1);
    });
  });

  group('states', () {
    testWidgets('an empty account gets a starting point, not a blank page', (
      tester,
    ) async {
      await _show(tester, _harness(const [], _FakeChatRepository()));
      expect(find.textContaining('Start a conversation'), findsOneWidget);
    });
  });

  group('messaging somebody', () {
    testWidgets('another person opens their thread', (tester) async {
      final repository = _FakeChatRepository();
      await _showMessageButton(tester, repository, userId: 'u-salma');

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(repository.opened, ['u-salma']);
      expect(find.text('thread c-u-salma'), findsOneWidget);
    });

    testWidgets('yourself is refused before anything is written', (
      tester,
    ) async {
      final repository = _FakeChatRepository();
      await _showMessageButton(
        tester,
        repository,
        userId: 'u-me',
        signedInAs: 'u-me',
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(repository.opened, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('thread c-u-me'), findsNothing);
    });

    testWidgets('a thread that cannot be opened says so instead of moving', (
      tester,
    ) async {
      final repository = _FakeChatRepository(failToOpen: true);
      await _showMessageButton(tester, repository, userId: 'u-salma');

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('thread c-u-salma'), findsNothing);
    });
  });
}

/// A button that calls the shared "Message" path, over a router whose only
/// route past it reports which thread was opened.
Future<void> _showMessageButton(
  WidgetTester tester,
  _FakeChatRepository repository, {
  required String userId,
  String signedInAs = 'u-me',
}) async {
  final router = GoRouter(
    initialLocation: '/from',
    routes: [
      GoRoute(
        path: '/from',
        builder: (context, state) => _MessageButton(userId: userId),
      ),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) =>
            Text('thread ${state.pathParameters['conversationId']}'),
      ),
    ],
  );
  await _show(
    tester,
    ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        currentUserIdProvider.overrideWithValue(signedInAs),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
}

class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({required this.userId});

  final String userId;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () => messageUser(context, ref, widget.userId),
        child: const Text('go'),
      ),
    );
  }
}
