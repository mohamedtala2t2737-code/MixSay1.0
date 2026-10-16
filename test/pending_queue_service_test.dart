import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_chat/features/chat/pending_queue_service.dart';

Map<String, dynamic> _entry(String id) => {
  'client_id': id,
  'conversation_id': 'conversation',
  'sender_id': 'user',
  'created_at': DateTime.utc(2026).toIso8601String(),
  'content': 'message',
  'state': 'queued',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingQueueService', () {
    late PendingQueueService queue;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      queue = PendingQueueService(
        preferences: await SharedPreferences.getInstance(),
      );
    });

    test('serializes concurrent enqueues without losing messages', () async {
      await Future.wait(
        List.generate(40, (index) => queue.enqueue(_entry('$index'))),
      );

      expect(await queue.read(), hasLength(40));
    });

    test('serializes a flush transaction with concurrent enqueues', () async {
      await queue.enqueue(_entry('initial'));
      final flush = queue.runExclusive((transaction) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        transaction.entries.add(_entry('flushed'));
        await transaction.save();
      });
      final enqueue = queue.enqueue(_entry('parallel'));

      await Future.wait([flush, enqueue]);

      expect(
        (await queue.read()).map((entry) => entry['client_id']),
        containsAll(['initial', 'flushed', 'parallel']),
      );
    });

    test(
      'backs up corrupted queue data and starts with an empty queue',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(PendingQueueService.queueKey, '{bad json');

        expect(await queue.read(), isEmpty);
        expect(
          preferences.getKeys().any(
            (key) => key.startsWith('pending_chat_messages_corrupt_'),
          ),
          isTrue,
        );
        expect(preferences.getString(PendingQueueService.queueKey), '[]');
      },
    );

    test('deleting a queued attachment deletes its staged file', () async {
      final directory = Directory.systemTemp.createTempSync('mixsay-queue');
      addTearDown(() => directory.deleteSync(recursive: true));
      final staged = File('${directory.path}/client-1.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await queue.enqueue({
        ..._entry('client-1'),
        'media_type': 'image',
        'local_path': staged.path,
        'file_name': 'client-1.jpg',
        'byte_size': 3,
      });

      await queue.delete(clientId: 'client-1', senderId: 'user');

      expect(await queue.read(), isEmpty);
      expect(staged.existsSync(), isFalse);
    });

    test('a queued gif owns no file, so deleting keeps whatever it names', () async {
      final directory = Directory.systemTemp.createTempSync('mixsay-queue');
      addTearDown(() => directory.deleteSync(recursive: true));
      // A remote url is not a path, but a same-named file could exist on disk;
      // forgetting the message must leave it alone.
      final lookalike = File('${directory.path}/giphy.gif')
        ..writeAsBytesSync([9]);
      await queue.enqueue({
        ..._entry('client-2'),
        'media_type': 'gif',
        'local_path': 'https://media.giphy.com/giphy.gif',
        'file_name': 'giphy.gif',
      });

      await queue.delete(clientId: 'client-2', senderId: 'user');

      expect(lookalike.existsSync(), isTrue);
    });

    test(
      'an attachment described with the wrong types is not read back',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          PendingQueueService.queueKey,
          jsonEncode([
            {
              ..._entry('client-3'),
              'media_type': 'image',
              'local_path': '/tmp/a.jpg',
              'byte_size': 'large',
            },
          ]),
        );

        expect(await queue.read(), isEmpty);
      },
    );

    test('classifies network and permanent errors', () {
      expect(
        classifyPendingQueueFailure(const SocketException('offline')),
        PendingQueueFailure.network,
      );
      expect(
        classifyPendingQueueFailure(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        PendingQueueFailure.network,
      );
      expect(
        classifyPendingQueueFailure(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        PendingQueueFailure.permanent,
      );
    });
  });
}
