import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/pending_queue_service.dart';

/// The chat decisions that do not need a Firestore connection: which document
/// id a pair of users maps to, what a conversation row means for the current
/// user, how a thread is ordered on screen, which status changes are legal, and
/// when a queued message is allowed to try again. Everything here mirrors
/// firestore.rules, so a drift between the two shows up as a failing test
/// instead of a message that silently never arrives.
ChatMessage _message({
  required String id,
  String? clientId,
  required DateTime createdAt,
  String senderId = 'alice',
  String content = 'hi',
  String status = 'sent',
}) => ChatMessage(
  id: id,
  conversationId: '5_alicebob',
  senderId: senderId,
  content: content,
  clientId: clientId,
  createdAt: createdAt,
  status: status,
);

Map<String, dynamic> _conversationData({
  int? unreadForAlice,
  int? unreadForBob,
  List<String> members = const ['alice', 'bob'],
}) => {
  'members': members,
  'participants': {
    'alice': {'username': 'alice', 'fullName': 'Alice', 'avatarUrl': null},
    'bob': {
      'username': 'bobby',
      'fullName': 'Bob',
      'avatarUrl': 'https://example.test/bob.jpg',
    },
  },
  'lastMessageContent': 'ahlan',
  'lastMessageAt': DateTime.utc(2026, 3, 4),
  'unreadCounts': {'alice': ?unreadForAlice, 'bob': ?unreadForBob},
};

void main() {
  group('conversation identity', () {
    test('matches the id formula firestore.rules enforces', () {
      // Rules: string(members[0].size()) + '_' + members[0] + members[1]
      // over the sorted member list.
      for (final pair in [
        ['alice', 'bob'],
        ['zoe', 'ab'],
        ['a', 'bbbb'],
      ]) {
        final sorted = [...pair]..sort();
        final expected = '${sorted[0].length}_${sorted[0]}${sorted[1]}';
        expect(ChatRepository.buildConversationId(pair), expected);
      }
    });

    test('the length prefix disambiguates ids that would otherwise collide', () {
      // Without the prefix, 'ab' + 'c' and 'a' + 'bc' would be the same id and
      // two different pairs would share one thread.
      expect(
        ChatRepository.buildConversationId(['ab', 'c']),
        isNot(ChatRepository.buildConversationId(['a', 'bc'])),
      );
    });

    test('recipientOf returns the other member and rejects odd rosters', () {
      expect(ChatRepository.recipientOf(['alice', 'bob'], 'alice'), 'bob');
      expect(ChatRepository.recipientOf(['bob', 'alice'], 'alice'), 'bob');
      expect(ChatRepository.recipientOf(['alice'], 'bob'), 'alice');
      expect(ChatRepository.recipientOf(['alice', 'bob'], 'mallory'), isNull);
      // A three-member document must not silently pick one recipient.
      expect(
        ChatRepository.recipientOf(['alice', 'bob', 'carol'], 'alice'),
        isNull,
      );
    });
  });

  group('conversation list rows', () {
    test('shows the other participant, never myself', () {
      final forAlice = ChatConversationPreview.fromData(
        id: '5_alicebob',
        data: _conversationData(unreadForAlice: 2),
        userId: 'alice',
      );
      expect(forAlice.otherUserId, 'bob');
      expect(forAlice.otherUsername, 'bobby');
      expect(forAlice.otherAvatarUrl, 'https://example.test/bob.jpg');
      expect(forAlice.unreadCount, 2);
      expect(forAlice.lastMessageAt, DateTime.utc(2026, 3, 4));

      final forBob = ChatConversationPreview.fromData(
        id: '5_alicebob',
        data: _conversationData(unreadForAlice: 2),
        userId: 'bob',
      );
      expect(forBob.otherUserId, 'alice');
      expect(forBob.otherUsername, 'alice');
      expect(forBob.unreadCount, 0);
    });

    test('a missing counter or a string counter is still a number', () {
      // Firestore stores integers, but a hand-edited document or a legacy write
      // can put a string there; the badge must not throw.
      final absent = ChatConversationPreview.fromData(
        id: '5_alicebob',
        data: _conversationData(),
        userId: 'alice',
      );
      expect(absent.unreadCount, 0);

      final asText = ChatConversationPreview.fromData(
        id: '5_alicebob',
        data: {
          ..._conversationData(),
          'unreadCounts': {'alice': '7'},
        },
        userId: 'alice',
      );
      expect(asText.unreadCount, 7);
    });

    test('a damaged document degrades to an empty row instead of throwing', () {
      final broken = ChatConversationPreview.fromData(
        id: 'damaged',
        data: const {},
        userId: 'alice',
      );
      expect(broken.otherUserId, '');
      expect(broken.otherFullName, '');
      expect(broken.unreadCount, 0);
      expect(broken.lastMessageAt, isNull);
    });

    test('a fresh profile replaces the copied participant names', () {
      final preview = ChatConversationPreview.fromData(
        id: '5_alicebob',
        data: _conversationData(),
        userId: 'alice',
      ).withPublicProfile({'username': 'bobby2', 'fullName': 'Bobby'});
      expect(preview.otherUsername, 'bobby2');
      expect(preview.otherFullName, 'Bobby');
      // The copy is replaced wholesale, so a profile without an avatar key
      // clears it rather than keeping a stale image.
      expect(preview.otherAvatarUrl, isNull);

      final renamed = preview.withPublicProfile(null);
      expect(renamed.otherUsername, 'bobby2');
      expect(renamed.otherFullName, 'Bobby');
    });
  });

  group('thread ordering', () {
    test('sorts oldest first, which is what the reversed list expects', () {
      final merged = ChatRepository.mergeMessages(
        [
          _message(id: 'm3', createdAt: DateTime.utc(2026, 1, 4)),
          _message(id: 'm1', createdAt: DateTime.utc(2026, 1, 2)),
        ],
        [
          _message(id: 'm2', createdAt: DateTime.utc(2026, 1, 3)),
          _message(id: 'm0', createdAt: DateTime.utc(2026, 1, 1)),
        ],
      );
      expect(merged.map((m) => m.id).toList(), ['m0', 'm1', 'm2', 'm3']);
    });

    test('messages sent in the same second keep no particular order', () {
      // List.sort is not stable, so a tie falls back to insertion order, which
      // depends on which query delivered the pair first. The screen shows the
      // timestamp to the second, so the swap is invisible; asserting an order
      // here would only freeze the current sort algorithm.
      final now = DateTime.utc(2026, 1, 1);
      final merged = ChatRepository.mergeMessages(
        [_message(id: 'first', createdAt: now)],
        [_message(id: 'second', createdAt: now)],
      );
      expect(merged.map((m) => m.id).toSet(), {'first', 'second'});
      expect(merged, hasLength(2));
    });

    test('replaces a queued copy instead of showing the message twice', () {
      final queued = _message(
        id: 'pending-c1',
        clientId: 'c1',
        createdAt: DateTime.utc(2026, 1, 1),
        status: 'sending',
      );
      final delivered = _message(
        id: 'c1',
        clientId: 'c1',
        createdAt: DateTime.utc(2026, 1, 1),
        status: 'sent',
      );

      final merged = ChatRepository.mergeMessages([queued], [delivered]);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'c1');
      expect(merged.single.status, 'sent');
    });

    test('keeps a server message and a pending one of someone else apart', () {
      final merged = ChatRepository.mergeMessages(
        [_message(id: 'c1', clientId: 'c1', createdAt: DateTime.utc(2026))],
        [
          _message(
            id: 'c2',
            clientId: 'c2',
            createdAt: DateTime.utc(2026),
            senderId: 'bob',
          ),
        ],
      );
      expect(merged, hasLength(2));
    });

    test('does not mutate the list it was given', () {
      final loaded = [_message(id: 'm1', createdAt: DateTime.utc(2026, 1, 1))];
      final merged = ChatRepository.mergeMessages(loaded, [
        _message(id: 'm2', createdAt: DateTime.utc(2026, 1, 2)),
      ]);
      expect(loaded, hasLength(1));
      expect(merged, hasLength(2));
    });
  });

  group('status transitions', () {
    test('only move forward: sent -> delivered -> read', () {
      expect(
        ChatRepository.canMoveStatus(from: 'sent', to: 'delivered'),
        isTrue,
      );
      expect(ChatRepository.canMoveStatus(from: 'sent', to: 'read'), isTrue);
      expect(
        ChatRepository.canMoveStatus(from: 'delivered', to: 'read'),
        isTrue,
      );

      expect(
        ChatRepository.canMoveStatus(from: 'read', to: 'delivered'),
        isFalse,
      );
      expect(ChatRepository.canMoveStatus(from: 'read', to: 'sent'), isFalse);
      expect(
        ChatRepository.canMoveStatus(from: 'delivered', to: 'sent'),
        isFalse,
      );
      expect(ChatRepository.canMoveStatus(from: 'sent', to: 'sent'), isFalse);
    });

    test('rejects a status the rules do not know either', () {
      for (final from in ['archived', '', 'read']) {
        expect(
          ChatRepository.canMoveStatus(from: from, to: 'read'),
          from == 'delivered',
          reason: '$from must not become readable',
        );
        expect(
          ChatRepository.canMoveStatus(from: from, to: 'delivered'),
          from == 'sent',
        );
      }
      expect(
        ChatRepository.canMoveStatus(from: 'sent', to: 'archived'),
        isFalse,
      );
    });
  });

  group('queue and retry', () {
    late PendingQueueService queue;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      queue = PendingQueueService(
        preferences: await SharedPreferences.getInstance(),
      );
    });

    Map<String, dynamic> queueEntry({
      String senderId = 'alice',
      String state = 'queued',
      String? nextAttemptAt,
      int? attempts,
    }) => {
      'client_id': 'c1',
      'conversation_id': '5_alicebob',
      'sender_id': senderId,
      'content': 'ahlan',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'state': state,
      'next_attempt_at': ?nextAttemptAt,
      'attempts': ?attempts,
    };

    test('only my own, non-failed entries are attempted', () {
      expect(
        ChatRepository.isReadyToSend(queueEntry(), senderId: 'alice'),
        isTrue,
      );
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(state: 'sending'),
          senderId: 'alice',
        ),
        isTrue,
      );
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(state: 'failed'),
          senderId: 'alice',
        ),
        isFalse,
      );
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(senderId: 'bob'),
          senderId: 'alice',
        ),
        isFalse,
      );
    });

    test('a backoff window in the future holds the message back', () {
      final now = DateTime.utc(2026, 5, 5, 12);
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(
            nextAttemptAt: now
                .add(const Duration(seconds: 30))
                .toIso8601String(),
          ),
          senderId: 'alice',
          now: now,
        ),
        isFalse,
      );
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(
            nextAttemptAt: now
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
          ),
          senderId: 'alice',
          now: now,
        ),
        isTrue,
      );
      expect(
        ChatRepository.isReadyToSend(
          queueEntry(nextAttemptAt: 'not a date'),
          senderId: 'alice',
          now: now,
        ),
        isTrue,
      );
    });

    test('backoff doubles per attempt and stops at five minutes', () {
      expect(ChatRepository.retryBackoff(1), const Duration(seconds: 2));
      expect(ChatRepository.retryBackoff(4), const Duration(seconds: 16));
      expect(ChatRepository.retryBackoff(8), const Duration(seconds: 256));
      expect(ChatRepository.retryBackoff(9), const Duration(seconds: 300));
      expect(ChatRepository.retryBackoff(20), const Duration(seconds: 300));
    });

    test('the attempt counter is clamped so the queue cannot overflow', () {
      expect(ChatRepository.nextAttemptCount(null), 1);
      expect(ChatRepository.nextAttemptCount(3), 4);
      expect(ChatRepository.nextAttemptCount('7'), 8);
      expect(ChatRepository.nextAttemptCount(99), 8);
      expect(ChatRepository.nextAttemptCount(-5), 1);
    });

    test(
      'a retry request clears the backoff so the flush picks it up',
      () async {
        final blocked = queueEntry(
          nextAttemptAt: DateTime.now()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        );
        await queue.enqueue(blocked);
        expect(
          ChatRepository.isReadyToSend(
            (await queue.read()).single,
            senderId: 'alice',
          ),
          isFalse,
        );

        await queue.setStateFor(
          clientId: 'c1',
          senderId: 'alice',
          state: 'queued',
        );
        final afterRetry = (await queue.read()).single;
        expect(afterRetry['state'], 'queued');
        expect(afterRetry.containsKey('next_attempt_at'), isFalse);
        expect(
          ChatRepository.isReadyToSend(afterRetry, senderId: 'alice'),
          isTrue,
        );
      },
    );

    test('enqueueing the same client id again replaces the entry', () async {
      await queue.enqueue(queueEntry(state: 'failed'));
      await queue.enqueue(queueEntry(state: 'queued'));
      final entries = await queue.read();
      expect(entries, hasLength(1));
      expect(entries.single['state'], 'queued');
    });

    test('a permanent failure is not retried but a network one is', () {
      expect(
        classifyPendingQueueFailure(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        PendingQueueFailure.permanent,
      );
      expect(
        classifyPendingQueueFailure(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        PendingQueueFailure.network,
      );
    });
  });
}
