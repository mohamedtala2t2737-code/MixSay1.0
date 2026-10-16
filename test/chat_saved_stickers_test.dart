import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/features/chat/chat_saved_stickers.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// The savedStickers block of `firestore.rules`, which is the contract the rows
/// written here have to keep. Cut at the next `match` so a check cannot pass by
/// reading a rule that belongs to another collection.
String get _rulesBlock {
  final rules = _read('firestore.rules');
  final start = rules.indexOf('match /savedStickers/{savedId}');
  expect(
    start,
    isNonNegative,
    reason: 'rules must hold the savedStickers block',
  );
  final end = rules.indexOf('match /', start + 1);
  return rules.substring(start, end < 0 ? rules.length : end);
}

void main() {
  group('what a bookmark may name', () {
    test('a bundled sticker becomes both halves and one row id', () {
      final saved = SavedSticker.fromStickerId('mixsay-friends/cat')!;
      expect(saved.packId, 'mixsay-friends');
      expect(saved.sticker, 'cat');
      expect(saved.rowId, 'mixsay-friends_cat');
      // The message keeps carrying the id it already had, so a saved sticker
      // sends exactly like the tray tile it came from.
      expect(saved.stickerId, 'mixsay-friends/cat');
      expect(saved.asset, 'assets/stickers/mixsay-friends/cat.png');
    });

    test('the halves rebuild the id the bubble paints', () {
      final saved = SavedSticker(
        packId: 'mixsay-friends',
        sticker: 'thumbs-up',
      );
      expect(chatStickerAssetOf(saved.stickerId), saved.asset);
      expect(saved.rowId, 'mixsay-friends_thumbs-up');
    });

    test('every picture the tray offers can be bookmarked', () {
      for (final pack in chatStickerPacks) {
        for (final sticker in pack.stickers) {
          final id = chatStickerId(pack, sticker);
          final saved = SavedSticker.fromStickerId(id);
          expect(
            saved,
            isNotNull,
            reason: '$id is in the tray, so it must save',
          );
          // The row id joins the halves with `_`; a half holding one would make
          // two stickers share a row.
          expect(saved!.rowId, '${pack.id}_$sticker');
          expect(
            SavedSticker.fromStickerId(saved.stickerId),
            saved,
            reason: 'a row has to read back as the sticker it names',
          );
        }
      }
    });

    test('an id with no pack, no name or a pack of its own is refused', () {
      expect(SavedSticker.fromStickerId(null), isNull);
      expect(SavedSticker.fromStickerId(''), isNull);
      expect(SavedSticker.fromStickerId('cat'), isNull);
      expect(SavedSticker.fromStickerId('/cat'), isNull);
      expect(SavedSticker.fromStickerId('mixsay-friends/'), isNull);
      expect(SavedSticker.fromStickerId('other-pack/cat'), isNull);
      expect(SavedSticker.fromStickerId('mixsay-friends/unicorn'), isNull);
      expect(SavedSticker.fromStickerId('mixsay-friends/cat/png'), isNull);
    });

    test('a file path or URL is never a bookmark', () {
      // What an uploaded sticker carries: a Storage path, not a pack reference,
      // so the shelf has nothing to hold and the UI offers nothing.
      expect(SavedSticker.fromStickerId('chats/c1/alice/sticker.png'), isNull);
      expect(SavedSticker.fromStickerId('https://example.com/cat.png'), isNull);
    });
  });

  group('a stored row', () {
    test('reads back as the sticker it names', () {
      final saved = SavedSticker.fromRow({
        'packId': 'mixsay-friends',
        'sticker': 'cat',
      })!;
      expect(saved.stickerId, 'mixsay-friends/cat');
    });

    test(
      'that is missing a half, or holds the wrong type, is not a bookmark',
      () {
        expect(SavedSticker.fromRow(null), isNull);
        expect(SavedSticker.fromRow({}), isNull);
        expect(SavedSticker.fromRow({'packId': 'mixsay-friends'}), isNull);
        expect(SavedSticker.fromRow({'sticker': 'cat'}), isNull);
        expect(SavedSticker.fromRow({'packId': 1, 'sticker': 'cat'}), isNull);
      },
    );

    test('from a pack this build dropped stays off the shelf', () {
      expect(
        SavedSticker.fromRow({'packId': 'old-pack', 'sticker': 'cat'}),
        isNull,
      );
    });

    test('is written as the three fields the rules list', () {
      final row = SavedSticker(
        packId: 'mixsay-friends',
        sticker: 'cat',
      ).toRow();
      expect(row.keys.toSet(), {'packId', 'sticker', 'savedAt'});
      expect(row['packId'], 'mixsay-friends');
      expect(row['sticker'], 'cat');
      // The clock is the server's: a device-stamped row is refused by the rules.
      expect(row['savedAt'], isA<FieldValue>());
    });

    test('the rules list exactly the fields the row writes', () {
      final block = _rulesBlock;
      // hasOnly(...) is what keeps a fourth field — a URL, a path, a size — out
      // of a bookmark, so the list in the rules and the map in Dart are one
      // contract and must not drift apart.
      expect(block, contains('hasOnly('));
      for (final field in SavedSticker(
        packId: 'mixsay-friends',
        sticker: 'cat',
      ).toRow().keys) {
        expect(
          block,
          contains("'$field'"),
          reason: 'the rules must accept $field',
        );
      }
      expect(block, isNot(contains('mediaUrl')));
      expect(block, isNot(contains('size')));
    });

    test('only the owner touches the shelf', () {
      final block = _rulesBlock;
      // get / list / create / delete all bind to the account, and no stranger
      // can read a bookmark.
      expect(block.contains('request.auth.uid == userId'), isTrue);
      expect(
        block,
        contains('allow delete: if signedIn() && request.auth.uid == userId;'),
      );
    });

    test('the ceiling the app counts to is the ceiling the rules read to', () {
      expect(
        _rulesBlock,
        contains('request.query.limit <= ${SavedStickerRepository.capacity}'),
      );
    });
  });

  group('the shelf as it is written', () {
    final repository = _read('lib/features/chat/chat_saved_stickers.dart');

    test('is a subcollection of the account that owns it', () {
      expect(
        repository,
        contains(
          "_firestore.collection('users').doc(userId).collection('savedStickers')",
        ),
      );
    });

    test('the shelf is counted with the page the rules allow', () {
      // Rules cannot count a collection and refuse an aggregate, so the only
      // ceiling probe left is the page the rules do bound.
      expect(repository, contains('.limit(capacity).get()'));
    });

    test('a duplicate tap settles on one read', () {
      expect(repository, contains('if ((await row.get()).exists)'));
    });

    test('the newest save leads the stream', () {
      expect(repository, contains(".orderBy('savedAt', descending: true)"));
      expect(repository, contains('.limit(capacity)'));
    });

    test('a row of the shelf is keyed by both halves', () {
      expect(repository, contains('.doc(sticker.rowId)'));
    });

    test('removing an unknown id writes nothing', () {
      expect(repository, contains('if (sticker == null) return;'));
      expect(repository, contains('.doc(sticker.rowId).delete();'));
    });

    test('the providers hand the screen the shelf', () {
      final providers = _read('lib/features/chat/chat_providers.dart');
      expect(providers, contains('savedStickerRepositoryProvider'));
      expect(providers, contains('savedStickersProvider'));
    });
  });

  test('two bookmarks of one sticker are one row', () {
    final first = SavedSticker.fromStickerId('mixsay-friends/cat')!;
    final second = SavedSticker.fromStickerId('mixsay-friends/cat')!;
    expect(second, first);
    expect({first, second}.length, 1);
    expect(first.hashCode, second.hashCode);
  });
}
