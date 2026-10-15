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
