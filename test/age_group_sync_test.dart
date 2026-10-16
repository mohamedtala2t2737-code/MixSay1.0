import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Age groups are a server-side privacy boundary, so the shape of the client
/// that feeds it is the thing worth locking down: where the group comes from,
/// when it is written, and what the search asks for.
void main() {
  String source(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  group('sign-up', () {
    test('the profile is created with a group, not without one', () {
      final signed = source(
        'lib/features/auth/data/firebase_auth_repository.dart',
      );
      final profile = signed.substring(
        signed.indexOf("_publicProfiles.doc(user.uid)"),
      );
      expect(profile, contains("'ageGroup': AgeGroup.of("));
      expect(profile, contains('birthDate: birthDate,'));
    });

    test('the public profile adds one field and no age', () {
      final signed = source(
        'lib/features/auth/data/firebase_auth_repository.dart',
      );
      final row = signed.substring(
        signed.indexOf("_publicProfiles.doc(user.uid)"),
        signed.indexOf('});', signed.indexOf("_publicProfiles.doc(user.uid)")),
      );
      expect(row, contains("'ageGroup'"));
      // The date is read to work the group out; it is never stored alongside.
      expect(row, isNot(contains("'birthDate'")));
      expect(row, isNot(contains('age:')));
    });
  });

  group('healing an account that has no group yet', () {
    test('the group comes from the private birth date, never from a pick', () {
      final service = source('lib/features/auth/data/age_group_service.dart');
      expect(service, contains("collection('users')"));
      expect(service, contains('.doc(userId)'));
      expect(service, contains("['birthDate']"));
      expect(service, contains('AgeGroup.of('));
      // The only write is one field, to the caller's own public profile.
      expect(service, contains("collection('publicProfiles')"));
      expect(service, contains("'ageGroup': group.wire"));
      expect(service, isNot(contains('set(')));
    });

    test(
      'the write only happens when the stored group is not the right one',
      () {
        final service = source('lib/features/auth/data/age_group_service.dart');
        expect(service, contains("fromWire(profile.data()?['ageGroup'])"));
        expect(service, contains('!= group'));
      },
    );

    test('the same account is not re-read on every search', () {
      final service = source('lib/features/auth/data/age_group_service.dart');
      expect(service, contains('_settled[userId]'));
    });

    test('an app start is what runs it', () {
      final app = source('lib/app.dart');
      expect(app, contains('ref.read(ageGroupProvider.future)'));
      final providers = source(
        'lib/features/auth/presentation/auth_providers.dart',
      );
      expect(providers, contains('currentUserIdProvider'));
      expect(providers, contains('.resolve(userId)'));
    });
  });

  group('the search query', () {
    final repository = source('lib/features/chat/chat_repository.dart');
    final start = repository.indexOf(
      'Future<List<ChatUserPreview>> searchUsers',
    );
    final body = repository.substring(
      start,
      repository.indexOf('}', repository.indexOf('.limit(20)', start)),
    );

    test('it settles the searcher\'s own group before asking for anybody', () {
      expect(
        body.indexOf('await _ageGroups.resolve(_me)'),
        lessThan(body.indexOf(".collection('publicProfiles')")),
        reason: 'an unset group must fail, not return the whole range',
      );
    });

    test('it asks the server for one group and one username range', () {
      expect(body, contains(".where('ageGroup', isEqualTo: group.wire)"));
      expect(body, contains(".orderBy('usernameLowercase')"));
      expect(body, contains('.limit(20)'));
    });

    test('the repository is the one place that decides the filter', () {
      // Every caller shares one entry point, so no screen can build a search
      // that asks for the other group.
      expect(
        source('lib/features/search/presentation/search_screen.dart'),
        contains('searchUsers(query)'),
      );
      expect(
        source('lib/features/chat/chat_forward_sheet.dart'),
        contains('searchUsers'),
      );
      expect(
        source('lib/features/chat/conversations_view.dart'),
        contains('searchUsers'),
      );
    });

    test('the group filter needs an index and the rule needs a limit', () {
      final rules = source('firestore.rules');
      expect(rules, contains('request.query.limit <= 20'));
    });
  });

  group('the rules decide the group', () {
    test('a profile cannot pick its own group', () {
      final rules = source('firestore.rules');
      final profiles = rules.substring(
        rules.indexOf('match /publicProfiles/{userId}'),
      );
      expect(profiles, contains("request.resource.data.get('ageGroup', '')"));
      expect(
        profiles,
        contains("|| request.resource.data.get('ageGroup', '') =="),
      );
    });

    test('a list only shows the searcher their own group', () {
      final rules = source('firestore.rules');
      final profiles = rules.substring(
        rules.indexOf('match /publicProfiles/{userId}'),
      );
      expect(profiles, contains("ownAgeGroup() != ''"));
      expect(
        profiles,
        contains("resource.data.get('ageGroup', '') == ownAgeGroup()"),
      );
    });

    test('reading one profile by id still works for a foreign group', () {
      final rules = source('firestore.rules');
      final profiles = rules.substring(
        rules.indexOf('match /publicProfiles/{userId}'),
      );
      expect(profiles, contains('allow get: if verifiedUser();'));
    });

    test('a brand new thread needs both members in one group', () {
      final rules = source('firestore.rules');
      final gate = rules.substring(
        rules.indexOf('function membersShareAgeGroup'),
      );
      expect(gate, contains('computedAgeGroup(members[0])'));
      expect(gate, contains("first != ''"));
      expect(gate, contains('computedAgeGroup(members[1])'));

      final conversations = rules.substring(
        rules.indexOf('match /conversations/{conversationId}'),
      );
      final create = conversations.substring(
        0,
        conversations.indexOf('allow update'),
      );
      expect(create, contains('membersShareAgeGroup(request.resource.data'));
      // Only creation is gated, so a thread that predates the rule keeps
      // working for both sides.
      expect(conversations.substring(conversations.indexOf('allow update')),
          isNot(contains('membersShareAgeGroup')));
    });
  });

  group('nothing about age reaches the screen', () {
    test('no presentation file names a group or an age', () {
      // A provider living next to the screens is plumbing, not something a
      // user can see, so only drawing files are checked.
      final screens = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.replaceAll('\\', '/').contains('/presentation/') &&
                !file.path.endsWith('_providers.dart') &&
                file.path.endsWith('.dart'),
          );
      for (final file in screens) {
        final text = source(file.path);
        final path = file.path.replaceAll('\\', '/');
        expect(text, isNot(contains('ageGroup')), reason: path);
        expect(text, isNot(contains('AgeGroup')), reason: path);
        expect(text, isNot(contains('Slider')), reason: path);
      }
    });

    test('a result row carries no age field', () {
      final repository = source('lib/features/chat/chat_repository.dart');
      final start = repository.indexOf('class ChatUserPreview');
      final preview = repository.substring(
        start,
        repository.indexOf('class ', start + 6),
      );
      final fields = RegExp(r'^\s*final\s+\S+\s+(\w+);', multiLine: true)
          .allMatches(preview)
          .map((match) => match.group(1)!.toLowerCase())
          .toList();
      expect(fields, ['id', 'username', 'fullname', 'avatarurl']);
    });
  });
}
