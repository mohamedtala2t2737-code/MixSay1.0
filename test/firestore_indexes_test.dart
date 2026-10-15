import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Firestore emulator never enforces composite indexes, so a query whose
/// index does not match its shape passes every rule check and then fails on a
/// real project with `failed-precondition`. These tests compare the query
/// shapes in the repository with the indexes that are actually declared.
void main() {
  final declaredIndexes =
      jsonDecode(File('firestore.indexes.json').readAsStringSync())['indexes']
          as List<dynamic>;

  List<String> indexFields(Map<String, dynamic> index) =>
      (index['fields'] as List<dynamic>).cast<Map<String, dynamic>>().map((
        field,
      ) {
        final path = field['fieldPath'];
        if (field.containsKey('arrayConfig')) {
          return '$path ${field['arrayConfig']}';
        }
        return '$path ${field['order']}';
      }).toList();

  Map<String, dynamic>? indexFor(String collection, List<String> fields) {
    for (final index in declaredIndexes.cast<Map<String, dynamic>>()) {
      if (index['collectionGroup'] == collection &&
          indexFields(index).join(',') == fields.join(',')) {
        return index;
      }
    }
    return null;
  }

  test('the conversation list query has a matching array-contains index', () {
    // ChatRepository.watchConversations, fetchOlderConversations (the cursor
    // page) and markReceivedMessagesDelivered all filter `members` with
    // arrayContains and order by lastMessageAt, so the index must use CONTAINS
    // on members, not an ordering.
    expect(
      indexFor('conversations', [
        'members CONTAINS',
        'lastMessageAt DESCENDING',
      ]),
      isNotNull,
      reason:
          'an arrayContains filter cannot be served by an ASCENDING index '
          'entry on the same field',
    );
  });

  test('the delivered sweep has a matching message index', () {
    expect(
      indexFor('messages', [
        'recipientId ASCENDING',
        'status ASCENDING',
        'createdAt DESCENDING',
      ]),
      isNotNull,
    );
  });

  test('each profile content tab has a matching post index', () {
    // FeedRepository.fetchPostsByAuthorAndType filters authorId and mediaType
    // and orders by createdAt, so all three fields have to be in one index or
    // the query works in the emulator and fails on the real project.
    expect(
      indexFor('posts', [
        'authorId ASCENDING',
        'mediaType ASCENDING',
        'createdAt DESCENDING',
      ]),
      isNotNull,
    );
    // The untyped wall keeps its own index: the header counter still uses it.
    expect(
      indexFor('posts', ['authorId ASCENDING', 'createdAt DESCENDING']),
      isNotNull,
    );
  });

  test('every index is a collection-scope one', () {
    for (final index in declaredIndexes.cast<Map<String, dynamic>>()) {
      expect(index['collectionGroup'], isNotEmpty);
      expect(index['queryScope'], 'COLLECTION');
    }
  });

  test('the profile tab query filters the type on the server', () {
    final source = File('lib/features/feed/data/feed_repository.dart')
        .readAsStringSync();
    final start = source.indexOf('fetchPostsByAuthorAndType');
    final body = source.substring(start, start + 1400);

    expect(body, contains("where('authorId', isEqualTo: authorId)"));
    expect(body, contains("where('mediaType', isEqualTo: mediaType)"));
    expect(body, contains("orderBy('createdAt', descending: true)"));
    expect(body, contains('startAfterDocument(after)'));
    expect(body, contains('limit(limit)'));
    // The page size is what the list rule allows, and nothing bigger.
    expect(File('firestore.rules').readAsStringSync(),
        contains('request.query.limit <= 30'));
    expect(source, contains('static const postPageSize = 30'));
    expect(body, contains('int limit = postPageSize'));
  });

  test('the profile tabs never filter a mixed page on the client', () {
    final screen = File(
      'lib/features/profile/presentation/profile_screen.dart',
    ).readAsStringSync();

    // The old wall read one mixed list and picked the clips out of it, which
    // showed too few tiles and broke the cursor.
    expect(screen, isNot(contains('mediaType ==')));
    expect(screen, isNot(contains(".where((post)")));
  });

  test('every arrayContains query in the repository is indexed', () {
    final source = File('lib/features/chat/chat_repository.dart')
        .readAsStringSync();

    final arrayContainsFields = RegExp(
      r"where\(\s*'([A-Za-z]+)',\s*arrayContains:",
    ).allMatches(source).map((match) => match.group(1)!).toSet();

    expect(arrayContainsFields, contains('members'));
    for (final field in arrayContainsFields) {
      final hasContainsEntry = declaredIndexes.cast<Map<String, dynamic>>().any(
        (index) =>
            (index['fields'] as List<dynamic>).cast<Map<String, dynamic>>().any(
              (entry) =>
                  entry['fieldPath'] == field &&
                  entry['arrayConfig'] == 'CONTAINS',
            ),
      );
      expect(hasContainsEntry, isTrue, reason: '$field needs an ARRAY index');
    }
  });
}
