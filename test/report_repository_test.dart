import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/features/reports/data/report_repository.dart';

/// The report writes are the one place where a Dart constant and a rules
/// constant have to agree exactly, so the agreement is checked against the real
/// `firestore.rules` text instead of against a copy of it.
void main() {
  final rules = File('firestore.rules').readAsStringSync();

  List<String> quotedIn(String pattern) => RegExp(pattern, dotAll: true)
      .firstMatch(rules)!
      .group(1)!
      .split(',')
      .map((value) => value.trim().replaceAll("'", ''))
      .toList();

  test('the reasons the app can send are the reasons the rules allow', () {
    expect(
      quotedIn(r"reason in \[(.*?)\]"),
      ReportReason.values.map((reason) => reason.value).toList(),
    );
  });

  test('the target types the app can name are the ones the rules allow', () {
    expect(
      quotedIn(r"targetType in \[(.*?)\]"),
      ReportTarget.values.map((target) => target.value).toList(),
    );
  });

  test('the note limit matches the rule length', () {
    final sizeLimit = RegExp(r'extraNote\.size\(\) <= (\d+)')
        .firstMatch(rules)!
        .group(1);
    expect(ReportRepository.noteMaxLength, int.parse(sizeLimit!));
  });

  test('a blank note is dropped and a real one is trimmed', () {
    expect(ReportRepository.normalizeNote(null), isNull);
    expect(ReportRepository.normalizeNote(''), isNull);
    expect(ReportRepository.normalizeNote('   '), isNull);
    expect(
      ReportRepository.normalizeNote('  he insulted me  '),
      'he insulted me',
    );
  });
}
