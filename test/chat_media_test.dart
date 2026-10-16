import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/features/chat/chat_media.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

void main() {
  final photo = ChatAttachmentDraft(
    type: ChatMessageType.image,
    localPath: '/tmp/pending/photo-1.jpg',
    fileName: 'photo-1.jpg',
    byteSize: 400 * 1024,
  );

  group('queue JSON', () {
    test('a draft survives the trip through the queue', () {
      final entry = {
        'client_id': 'c-1',
        ...ChatAttachmentDraft(
          type: ChatMessageType.voice,
          localPath: '/tmp/pending/c-1.m4a',
          fileName: 'c-1.m4a',
          byteSize: 22000,
          caption: 'sabah el khir',
          durationMs: 4200,
        ).toQueueFields(),
      };

      final restored = ChatAttachmentDraft.fromQueueFields(entry)!;

      expect(restored.type, ChatMessageType.voice);
      expect(restored.localPath, '/tmp/pending/c-1.m4a');
      expect(restored.byteSize, 22000);
      expect(restored.caption, 'sabah el khir');
      expect(restored.durationMs, 4200);
    });

    test('a message with no attachment describes none', () {
      expect(
        photo.copyWith(caption: '').toQueueFields().containsKey('caption'),
        isFalse,
      );
      expect(ChatAttachmentDraft.fromQueueFields({'client_id': 'c-2'}), isNull);
    });

    test('an entry from the photo-only build is still a photo', () {
      final legacy = ChatAttachmentDraft.fromQueueFields({
        'local_image_path': '/tmp/pending/old.jpg',
      })!;

      expect(legacy.type, ChatMessageType.image);
      expect(legacy.fileName, 'old.jpg');
      // A queue entry from that build never carried a size, so nothing here
      // claims one; the repository measures the file before it uploads.
      expect(legacy.byteSize, 0);
    });

    test('only an upload owns a file on this device', () {
      expect(
        ChatAttachmentDraft.queuedFilePaths({
          'media_type': 'video',
          'local_path': '/tmp/pending/v.mp4',
        }),
        ['/tmp/pending/v.mp4'],
      );
      expect(
        ChatAttachmentDraft.queuedFilePaths({
          'media_type': 'gif',
          'local_path': 'https://media.tenor.com/x.gif',
        }),
        isEmpty,
      );
      expect(
        ChatAttachmentDraft.queuedFilePaths({'content': 'hello'}),
        isEmpty,
      );
    });

    test('a queued clip owns its poster too, so nothing is left behind', () {
      final entry = {
        'media_type': 'video',
        'local_path': '/tmp/pending/v.mp4',
        'thumb_local_path': '/tmp/pending/v_thumb.jpg',
      };

      expect(ChatAttachmentDraft.queuedFilePaths(entry), [
        '/tmp/pending/v.mp4',
        '/tmp/pending/v_thumb.jpg',
      ]);
      expect(ChatAttachmentDraft.queueFieldsAreValid(entry), isTrue);
      expect(
        ChatAttachmentDraft.queueFieldsAreValid({
          ...entry,
          'thumb_local_path': '',
        }),
        isFalse,
      );
    });

    test('a poster survives the round trip through the queue', () {
      final draft = ChatAttachmentDraft(
        type: ChatMessageType.video,
        localPath: '/tmp/pending/v.mp4',
        fileName: 'v.mp4',
        byteSize: 4 * 1024 * 1024,
        thumbnailPath: '/tmp/pending/v_thumb.jpg',
        durationMs: 9000,
      );
      final rebuilt = ChatAttachmentDraft.fromQueueFields(
        draft.toQueueFields(),
      );

      expect(rebuilt?.thumbnailPath, '/tmp/pending/v_thumb.jpg');
      expect(rebuilt?.durationMs, 9000);
    });

    test('a poster lands beside the clip, in the senders own folder', () {
      final draft = ChatAttachmentDraft(
        type: ChatMessageType.video,
        localPath: '/tmp/pending/v.mp4',
        fileName: 'v.mp4',
        byteSize: 4 * 1024 * 1024,
        thumbnailPath: '/tmp/pending/v_thumb.jpg',
      );

      expect(
        draft.thumbnailStoragePath(
          conversationId: 'c1',
          senderId: 'u1',
          clientId: 'm9',
        ),
        'chats/c1/u1/m9_thumb.jpg',
      );
      // The object name is what the rules count, so both halves stay in the
      // same four-part path.
      expect(
        draft
            .thumbnailStoragePath(
              conversationId: 'c1',
              senderId: 'u1',
              clientId: 'm9',
            )
            .split('/'),
        hasLength(4),
      );
    });

    test('a description with the wrong shape is refused', () {
      expect(
        ChatAttachmentDraft.queueFieldsAreValid({
          'media_type': 'image',
          'local_path': '',
        }),
        isFalse,
      );
      expect(
        ChatAttachmentDraft.queueFieldsAreValid({
          'local_path': '/tmp/a.jpg',
          'byte_size': 'large',
        }),
        isFalse,
      );
      expect(
        ChatAttachmentDraft.queueFieldsAreValid({
          'local_path': '/tmp/a.jpg',
          'duration_ms': -1,
        }),
        isFalse,
      );
      expect(
        ChatAttachmentDraft.queueFieldsAreValid({
          'media_type': 'file',
          'local_path': '/tmp/a.pdf',
          'file_name': 'a.pdf',
          'byte_size': 10,
        }),
        isTrue,
      );
    });
  });

  group('upload naming', () {
    test('the object lands in the senders own conversation folder', () {
      final path = photo.storagePath(
        conversationId: 'conv-1',
        senderId: 'u-me',
        clientId: 'c-1',
      );

      expect(path, 'chats/conv-1/u-me/c-1.jpg');
      // `chatUploadPathIsMine()` in firestore.rules counts four parts.
      expect(path.split('/'), hasLength(4));
    });

    test('a document keeps the extension the receiver opens it with', () {
      expect(
        ChatAttachmentDraft(
          type: ChatMessageType.file,
          localPath: '/tmp/report',
          fileName: 'Report.PDF',
          byteSize: 1,
        ).storageObjectName('c-2'),
        'c-2.pdf',
      );
    });
  });

  group('content types', () {
    test('each kind declares the type its rules ceiling reads', () {
      expect(chatMediaType(ChatMessageType.image, 'a.jpg'), 'image/jpeg');
      expect(chatMediaType(ChatMessageType.video, 'a.mov'), 'video/quicktime');
      expect(chatMediaType(ChatMessageType.voice, 'a.m4a'), 'audio/m4a');
      expect(chatMediaType(ChatMessageType.gif, 'a.gif'), 'image/gif');
      expect(chatMediaType(ChatMessageType.file, 'a.pdf'), 'application/pdf');
      expect(chatMediaType(ChatMessageType.file, 'a.unknown'), isNot(isEmpty));
    });

    test('an unknown document is octet-stream, never a guess', () {
      expect(
        chatMediaType(ChatMessageType.file, 'notes.xyz'),
        'application/octet-stream',
      );
    });
  });

  group('size ceilings', () {
    test('every uploaded kind has a ceiling and a gif has none', () {
      expect(chatMediaLimitFor(ChatMessageType.image), isNotNull);
      expect(chatMediaLimitFor(ChatMessageType.video), isNotNull);
      expect(chatMediaLimitFor(ChatMessageType.file), isNotNull);
      expect(chatMediaLimitFor(ChatMessageType.voice), isNotNull);
      expect(chatMediaLimitFor(ChatMessageType.gif), isNull);
    });

    test('a file over its own ceiling is refused before it travels', () {
      final huge = photo.copyWith(byteSize: 9 * 1024 * 1024);

      final rejection = chatMediaRejection(huge)!;

      expect(rejection.reason, 'tooLarge');
      expect(rejection.limitBytes, chatMediaLimitFor(ChatMessageType.image));
    });

    test('the same bytes are fine for a video', () {
      final clip = ChatAttachmentDraft(
        type: ChatMessageType.video,
        localPath: '/tmp/a.mp4',
        fileName: 'a.mp4',
        byteSize: 9 * 1024 * 1024,
      );

      expect(chatMediaRejection(clip), isNull);
    });

    test('an empty file is unusable rather than a zero-byte upload', () {
      expect(chatMediaRejection(photo.copyWith(byteSize: 0))!.reason, 'empty');
    });
  });

  test('a draft with no recorded size measures its file', () async {
    final directory = Directory.systemTemp.createTempSync('mixsay-media');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    final unmeasured = ChatAttachmentDraft(
      type: ChatMessageType.image,
      localPath: file.path,
      fileName: 'a.jpg',
      byteSize: 0,
    );

    final measured = await unmeasured.withMeasuredSize();

    expect(measured.byteSize, 3);
    // A draft that already knows its size is trusted, so nothing re-reads a
    // file the sender was shown the label of.
    expect((await photo.withMeasuredSize()).byteSize, photo.byteSize);
  });

  group('a queued message rendered before it is sent', () {
    ChatMessage pending(Map<String, dynamic> extra) => ChatMessage.fromPending({
      'client_id': 'c-1',
      'conversation_id': 'conv-1',
      'sender_id': 'u-me',
      'created_at': DateTime.utc(2026, 3, 4).toIso8601String(),
      'state': 'queued',
      ...extra,
    });

    test('a photo bubble reads the staged file, not Storage', () {
      final message = pending({
        'media_type': 'image',
        'local_path': '/tmp/pending/c-1.jpg',
        'file_name': 'c-1.jpg',
        'byte_size': 1200,
      });

      expect(message.type, ChatMessageType.image);
      expect(message.localImagePath, '/tmp/pending/c-1.jpg');
      expect(message.mediaPath, '/tmp/pending/c-1.jpg');
      expect(message.fileSize, 1200);
      // A staging name means nothing to the receiver, so only a document is
      // given a label to show.
      expect(message.fileName, isNull);
    });

    test('a document carries the name the receiver opens', () {
      final message = pending({
        'content': 'here you go',
        'media_type': 'file',
        'local_path': '/tmp/pending/c-1.pdf',
        'file_name': 'Contract.pdf',
        'byte_size': 1200,
      });

      expect(message.fileName, 'Contract.pdf');
      expect(message.content, 'here you go');
    });

    test('a gif carries its url instead of a local file', () {
      final message = pending({
        'media_type': 'gif',
        'local_path': 'https://media.tenor.com/hi.gif',
        'file_name': 'hi.gif',
      });

      expect(message.mediaPath, 'https://media.tenor.com/hi.gif');
      expect(message.localImagePath, isNull);
      expect(message.inferredType(), ChatMessageType.gif);
    });

    test('a text-only queue entry stays text', () {
      final message = pending({'content': 'ahlan'});

      expect(message.type, ChatMessageType.text);
      expect(message.mediaPath, isNull);
      expect(message.fileSize, isNull);
    });

    test('a voice note keeps its length for the player', () {
      final message = pending({
        'media_type': 'voice',
        'local_path': '/tmp/pending/c-1.m4a',
        'file_name': 'c-1.m4a',
        'byte_size': 9000,
        'duration_ms': 3000,
      });

      expect(message.durationMs, 3000);
      expect(message.type, ChatMessageType.voice);
    });

    test('a legacy photo entry still looks like a photo', () {
      final message = pending({'local_image_path': '/tmp/pending/old.jpg'});

      expect(message.type, ChatMessageType.image);
      expect(message.localImagePath, '/tmp/pending/old.jpg');
      expect(message.fileSize, isNull);
    });
  });

  group('the name a sender gives their file', () {
    test('keeps a plain document name as it is', () {
      expect(chatSafeReceivedName('My Report (1).pdf'), 'My Report (1).pdf');
    });

    test('shows only the file, never the folder it came from', () {
      expect(chatSafeReceivedName('/home/sama/notes/week 3.txt'), 'week 3.txt');
      expect(chatSafeReceivedName(r'C:\Users\sama\x.pdf'), 'x.pdf');
    });

    test('drops what a filesystem on the receiver would refuse', () {
      expect(chatSafeReceivedName('report:final?.pdf'), 'reportfinal.pdf');
      expect(chatSafeReceivedName('a\u0000b.txt'), 'ab.txt');
    });

    test('falls back when the name says nothing', () {
      expect(chatSafeReceivedName(null), 'attachment');
      expect(chatSafeReceivedName(''), 'attachment');
      expect(chatSafeReceivedName('   '), 'attachment');
      expect(chatSafeReceivedName('...'), 'attachment');
      expect(chatSafeReceivedName('../../'), 'attachment');
    });

    test('cuts a long name but keeps the part you open it with', () {
      final long = 'a' * 120;
      final shown = chatSafeReceivedName('$long.pdf');

      expect(shown.length, lessThan(long.length));
      expect(shown, endsWith('.pdf'));
      expect(chatSafeReceivedName('b' * 200), isNot(contains('.')));
    });
  });

  group('a picked clip and a picked document', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('mixsay_chat_media'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('a clip keeps its own extension under the message id', () async {
      final source = File('${temp.path}/IMG_0234.MOV')
        ..writeAsStringSync('bytes');
      final draft = await chatVideoDraft(
        pickedPath: source.path,
        pickedName: 'IMG_0234.MOV',
        clientId: 'c-9',
      );

      expect(draft.type, ChatMessageType.video);
      expect(draft.fileName, 'c-9.mov');
      expect(draft.storageObjectName('c-9'), 'c-9.mov');
      expect(draft.contentType, 'video/quicktime');
      expect(draft.byteSize, 5);
    });

    test('a clip with nothing to tell its format goes as the default mp4', () async {
      final source = File('${temp.path}/clip')..writeAsStringSync('bytes');
      final draft = await chatVideoDraft(
        pickedPath: source.path,
        pickedName: 'clip',
        clientId: 'c-9',
      );

      expect(draft.fileName, 'c-9.mp4');
      expect(draft.contentType, 'video/mp4');
    });

    test('an unreadable clip is refused instead of sent as nothing', () async {
      final source = File('${temp.path}/empty.mp4')..createSync();
      final draft = await chatVideoDraft(
        pickedPath: source.path,
        pickedName: 'empty.mp4',
        clientId: 'c-9',
      );

      expect(chatMediaRejectionReason(draft), 'empty');
    });

    test('a document is copied beside the queue and keeps the name its sender gave it', () async {
      final source = File('${temp.path}/origin.pdf')..writeAsStringSync('invoice');
      final draft = await chatDocumentDraft(
        fileName: 'Invoice (final).pdf',
        pickedPath: source.path,
        pickedBytes: null,
        directory: temp.path,
        clientId: 'c-10',
      );

      expect(draft.type, ChatMessageType.file);
      expect(draft.fileName, 'Invoice (final).pdf');
      expect(draft.localPath, isNot(source.path));
      expect(File(draft.localPath).readAsStringSync(), 'invoice');
      expect(draft.byteSize, 7);
      expect(draft.contentType, 'application/pdf');
    });

    test('a uri the app cannot open is taken as bytes instead', () async {
      final draft = await chatDocumentDraft(
        fileName: 'notes.txt',
        pickedPath: null,
        pickedBytes: Uint8List.fromList(utf8.encode('ahla')),
        directory: temp.path,
        clientId: 'c-11',
      );

      expect(File(draft.localPath).readAsStringSync(), 'ahla');
      expect(draft.contentType, 'text/plain');
    });

    test('a pick that gave neither a path nor bytes is refused, not sent empty', () async {
      await expectLater(
        chatDocumentDraft(
          fileName: 'x.txt',
          pickedPath: null,
          pickedBytes: null,
          directory: temp.path,
          clientId: 'c-12',
        ),
        throwsA(isA<ChatAttachmentRejectedException>()),
      );
    });

    test('a document with no extension still lands in the message folder', () async {
      final draft = await chatDocumentDraft(
        fileName: 'README',
        pickedPath: null,
        pickedBytes: Uint8List.fromList([1, 2, 3]),
        directory: temp.path,
        clientId: 'c-13',
      );

      expect(draft.localPath, endsWith('/c-13'));
      expect(draft.byteSize, 3);
      expect(draft.contentType, 'application/octet-stream');
    });
  });
}
