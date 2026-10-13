import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/app_strings.dart';

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}

class EmailNotConfirmedException implements Exception {
  const EmailNotConfirmedException();
}

String describeUsernameCheckError(Object error, AppStrings s) {
  if (error is FormatException) return s.errInvalidUsername;

  if (error is FirebaseException) {
    final message = switch (error.code) {
      'permission-denied' ||
      'unauthenticated' => s.usernameCheckPermissionDenied,
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => s.errNetwork,
      'failed-precondition' => s.usernameCheckDatabaseUnavailable,
      _ => s.usernameCheckFailed,
    };
    return '$message (${s.usernameCheckErrorCode(error.code)})';
  }
  if (error is SocketException) return s.errNetwork;
  return s.usernameCheckFailed;
}

/// Maps any error thrown by Firebase auth to a short, user-friendly
/// message in the current language.
String describeAuthError(Object error, AppStrings s) {
  if (error is UsernameAlreadyTakenException ||
      error is EmailNotConfirmedException) {
    return error is UsernameAlreadyTakenException
        ? s.usernameTaken
        : s.errEmailNotConfirmed;
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'invalid-email':
      case 'user-not-found':
      case 'wrong-password':
        return s.errInvalidCredentials;
      case 'email-already-in-use':
        return s.errEmailTaken;
      case 'weak-password':
        return s.errWeakPassword;
      case 'too-many-requests':
        return s.errTooManyAttempts;
      case 'network-request-failed':
        return s.errNetwork;
    }
  }
  final text = error.toString().toLowerCase();
  if (error is SocketException ||
      text.contains('socketexception') ||
      text.contains('fetch failed') ||
      text.contains('failed host')) {
    return s.errNetwork;
  }
  return s.errGeneric;
}
