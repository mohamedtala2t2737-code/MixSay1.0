import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';

void main() {
  const strings = AppStrings(Locale('en'));

  test('explains when Firestore rules or App Check deny username lookup', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    expect(
      describeUsernameCheckError(error, strings),
      '${strings.usernameCheckPermissionDenied} '
      '(${strings.usernameCheckErrorCode('permission-denied')})',
    );
  });

  test('treats unavailable Firestore as a network failure', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );

    expect(
      describeUsernameCheckError(error, strings),
      '${strings.errNetwork} (${strings.usernameCheckErrorCode('unavailable')})',
    );
  });

  test('explains when the Firestore database is not ready', () {
    final error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'failed-precondition',
    );

    expect(
      describeUsernameCheckError(error, strings),
      '${strings.usernameCheckDatabaseUnavailable} '
      '(${strings.usernameCheckErrorCode('failed-precondition')})',
    );
  });

  test('distinguishes an invalid username from a failed lookup', () {
    expect(
      describeUsernameCheckError(
        const FormatException('Invalid username format'),
        strings,
      ),
      strings.errInvalidUsername,
    );
  });
}
