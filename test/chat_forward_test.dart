import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_forward.dart';
import 'package:social_chat/features/chat/chat_forward_sheet.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// The thread a test opens the picker from, so it can be left out of the list.
const _from = 'c-Here';

ChatMessage _message({
  String content = 'ahlan',
  ChatMessageType type = ChatMessageType.text,
  String? mediaPath,
  String? stickerId,
  bool deletedForEveryone = false,
}) => ChatMessage(
  id: 'm1',
  conversationId: 'c1',
  senderId: 'me',
  content: content,
  status: 'sent',
  type: type,
  mediaPath: mediaPath,
  stickerId: stickerId,
  deletedForEveryone: deletedForEveryone,
  createdAt: DateTime(2026, 10, 15, 9, 30),
);

void main() {
  group('what a copy may carry', () {
    test('words travel as words', () {
      final payload = ChatForwardPayload.from(_message());
      expect(payload?.type, ChatMessageType.text);
      expect(payload?.text, 'ahlan');
    });

    test('a bundled sticker travels by its id and uploads nothing', () {
      final payload = ChatForwardPayload.from(
        _message(
          content: '',
          type: ChatMessageType.sticker,
          stickerId: 'starter:cat',
        ),
      );
      expect(payload?.stickerId, 'starter:cat');
      expect(payload?.mediaUrl, isNull);
    });

    test('a GIF travels by the public url it already had', () {
      final payload = ChatForwardPayload.from(
        _message(
          type: ChatMessageType.gif,
          mediaPath: 'https://tenor.example/cat.gif',
        ),
      );
      expect(payload?.mediaUrl, 'https://tenor.example/cat.gif');
    });

    test('a picture, a clip, a document and a voice note have no arrow', () {
      for (final type in const [
        ChatMessageType.image,
        ChatMessageType.video,
        ChatMessageType.file,
        ChatMessageType.voice,
      ]) {
        expect(
          ChatForwardPayload.from(
            _message(type: type, mediaPath: 'chats/c1/me/one'),
          ),
          isNull,
          reason: '$type lives in this chat\'s own folder',
        );
      }
    });

    test('an uploaded sticker is a file of this chat, so it stays', () {
      expect(
        ChatForwardPayload.from(
          _message(
            content: '',
            type: ChatMessageType.sticker,
            stickerId: 'user:abc',
            mediaPath: 'chats/c1/me/sticker.png',
          ),
        ),
        isNull,
      );
    });

    test('a GIF pointing at my own Storage is not a public url', () {
      expect(
        ChatForwardPayload.from(
          _message(type: ChatMessageType.gif, mediaPath: 'chats/c1/me/a.gif'),
        ),
        isNull,
      );
    });

    test('a message with nothing to say and a tombstone offer nothing', () {
      expect(ChatForwardPayload.from(_message(content: '   ')), isNull);
      expect(
        ChatForwardPayload.from(_message(deletedForEveryone: true)),
        isNull,
      );
    });

    test('a document from before the type field reads as a picture', () {
      // The deciding call is [ChatMessage.inferredType], so a media row that
      // predates `type` is refused rather than sent as a copy of a text.
      expect(
        ChatForwardPayload.from(_message(mediaPath: 'chats/c1/me/a.jpg')),
        isNull,
      );
    });
  });

  group('a destination', () {
    test('a person with no chat yet is a new chat', () {
      expect(const ChatForwardTarget.newChat('u1').isNewChat, isTrue);
      expect(const ChatForwardTarget.conversation('c1').isNewChat, isFalse);
    });

    test('ticking the same place twice is one selection', () {
      expect(
        const ChatForwardTarget.conversation('c1'),
        const ChatForwardTarget.conversation('c1'),
      );
      final selected = <ChatForwardTarget>{};
      selected.add(const ChatForwardTarget.newChat('u1'));
      selected.add(const ChatForwardTarget.newChat('u1'));
      expect(selected.length, 1);
    });
  });

  group('the picker', () {
    testWidgets('the chat the message came from is not offered', (
      tester,
    ) async {
      await _open(tester, chats: [_chat('Here'), _chat('Salma')]);
      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('Here'), findsNothing);
    });

    testWidgets('nothing ticked means nothing to send', (tester) async {
      await _open(tester, chats: [_chat('Salma')]);
      expect(find.text('Send to 0'), findsOneWidget);
      expect(_sendButton(tester).onPressed, isNull);
    });

    testWidgets('each tick joins the list the copies go to', (tester) async {
      await _open(tester, chats: [_chat('Salma'), _chat('Omar')]);
      await tester.tap(find.text('Salma'));
      await tester.pump();
      expect(find.text('Send to 1'), findsOneWidget);

      await tester.tap(find.text('Omar'));
      await tester.pump();
      expect(_sendButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Send to 2'));
      await tester.pumpAndSettle();
      expect(_sent, [
        const ChatForwardTarget.conversation('c-Salma'),
        const ChatForwardTarget.conversation('c-Omar'),
      ]);
    });

    testWidgets('ticking a row again takes it back off', (tester) async {
      await _open(tester, chats: [_chat('Salma')]);
      await tester.tap(find.text('Salma'));
      await tester.pump();
      await tester.tap(find.text('Salma'));
      await tester.pump();
      expect(find.text('Send to 0'), findsOneWidget);
      expect(_sendButton(tester).onPressed, isNull);
    });

    testWidgets('closing the sheet without sending gives back nothing', (
      tester,
    ) async {
      await _open(tester, chats: [_chat('Salma')]);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(_sent, isNull);
    });

    testWidgets('the rows filter locally and only then ask for people', (
      tester,
    ) async {
      final repository = _FakeChatRepository();
      await _open(
        tester,
        chats: [_chat('Salma'), _chat('Omar')],
        repository: repository,
      );
      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump();
      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('Omar'), findsNothing);
      expect(repository.searches, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.searches, ['sal']);
    });

    testWidgets('a person with no chat yet is chosen under People', (
      tester,
    ) async {
      final repository = _FakeChatRepository(
        people: const [
          ChatUserPreview(id: 'u-new', username: 'newname', fullName: ''),
        ],
      );
      await _open(tester, chats: [_chat('Salma')], repository: repository);
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('People'), findsOneWidget);
      expect(find.text('@newname'), findsOneWidget);

      await tester.tap(find.text('@newname'));
      await tester.pump();
      await tester.tap(find.text('Send to 1'));
      await tester.pump();
      await tester.pump();
      expect(_sent, [const ChatForwardTarget.newChat('u-new')]);
    });

    testWidgets('a person already in my chats is not offered twice', (
      tester,
    ) async {
      final repository = _FakeChatRepository(
        people: const [
          ChatUserPreview(id: 'u-Salma', username: 'salma', fullName: 'Salma'),
        ],
      );
      await _open(tester, chats: [_chat('Salma')], repository: repository);
      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('People'), findsNothing);
    });

    testWidgets('a people search that fails keeps the chats on screen', (
      tester,
    ) async {
      final repository = _FakeChatRepository(failSearch: true);
      await _open(tester, chats: [_chat('Salma')], repository: repository);
      await tester.enterText(find.byType(TextField), 'sal');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Salma'), findsOneWidget);
      expect(find.text('No results'), findsNothing);
    });

    testWidgets('a chat list the backend refuses says so and can be retried', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          chats: null,
          repository: _FakeChatRepository(),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('the picker is translated like the rest of the thread', (
      tester,
    ) async {
      await _open(tester, chats: [_chat('Salma')], locale: const Locale('ar'));
      expect(find.text('حوّل الرسالة لـ'), findsOneWidget);
      expect(find.text('إرسال لـ ٠'), findsOneWidget);
    });

    test('the thread offers a forward only where a copy can travel', () {
      final source = _read('lib/features/chat/chat_screen.dart');
      expect(
        source,
        contains('final forwardPayload = ChatForwardPayload.from(message);'),
      );
      // One check decides the menu line, and the arrow only goes to artwork —
      // a sentence every two lines would otherwise bring a button with it.
      expect(source, contains('if (forwardPayload != null)'));
      expect(source, contains('final showsForwardArrow ='));
      expect(source, contains('onForward: showsForwardArrow'));
      expect(source, contains('forwardPayload.type != ChatMessageType.text'));
    });
  });

  group('the copy as it is written', () {
    test('a forward is a copy of the payload and uploads nothing', () {
      final source = _read('lib/features/chat/chat_repository.dart');
      expect(source, contains("if (forwarded) fields['forwarded'] = true;"));
      expect(source, contains("if (forwarded) 'forwarded': true,"));
      expect(source, contains("forwarded: entry['forwarded'] == true,"));
    });
  });
}

/// What the last sheet handed back, or null while it is still open.
List<ChatForwardTarget>? _sent;

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

ChatConversationPreview _chat(String name) => ChatConversationPreview(
  id: 'c-$name',
  otherUserId: 'u-$name',
  otherUsername: name.toLowerCase(),
  otherFullName: name,
  lastMessageContent: 'ahlan',
  lastMessageAt: DateTime(2026, 10, 15),
  unreadCount: 0,
  lastMessageType: ChatMessageType.text,
);

/// The repository the picker may search. Everything else about it is out of
/// this sheet's way, so an unfaked call is a loud failure.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository({this.people = const [], this.failSearch = false});

  final List<ChatUserPreview> people;
  final bool failSearch;
  final List<String> searches = [];

  @override
  Future<List<ChatUserPreview>> searchUsers(String query) async {
    searches.add(query);
    if (failSearch) throw StateError('firestore is not reachable');
    return people;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Widget _harness({
  required List<ChatConversationPreview>? chats,
  required _FakeChatRepository repository,
  required Locale locale,
}) => ProviderScope(
  overrides: [
    chatRepositoryProvider.overrideWithValue(repository),
    conversationsProvider.overrideWith(
      (ref) => chats == null
          ? Stream<List<ChatConversationPreview>>.error(
              StateError('no permission'),
            )
          : Stream.value(chats),
    ),
  ],
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
          onPressed: () async {
            _sent = await ChatForwardSheet.show(
              context,
              fromConversationId: _from,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

/// Opens the sheet the way the thread does: from a button, and waits for the
/// list and the localizations to arrive.
Future<void> _open(
  WidgetTester tester, {
  required List<ChatConversationPreview> chats,
  _FakeChatRepository? repository,
  Locale locale = const Locale('en'),
}) async {
  _sent = null;
  await tester.pumpWidget(
    _harness(
      chats: chats,
      repository: repository ?? _FakeChatRepository(),
      locale: locale,
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _sendButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));
