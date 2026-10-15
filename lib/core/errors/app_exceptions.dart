import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/app_strings.dart';

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}

class EmailNotConfirmedException implements Exception {
  const EmailNotConfirmedException();
}

/// The database refused a write that the client was sure about — in practice
/// the deployed Firestore rules. The user cannot fix this, so it needs its own
/// message instead of the generic "upload failed" one.
class PostRejectedException implements Exception {
  const PostRejectedException();
}

/// The Firebase error code of [error], or null when it carries none.
///
/// The code is the only thing that tells a missing composite index
/// (`failed-precondition`) apart from a rejected security rule
/// (`permission-denied`), and on a phone both look like "Failed to load".
String? firestoreErrorCode(Object? error) =>
    error is FirebaseException ? error.code : null;

/// One log line that keeps the exception type, the plugin, the code and the
/// server message — enough to name the cause without opening the console.
String describeFirestoreFailure(Object error) {
  if (error case FirebaseException(:final plugin, :final code, :final message)) {
    return '${error.runtimeType} [$plugin/$code] $message';
  }
  return '${error.runtimeType}: $error';
}

String describeUsernameCheckError(Object error, AppStrings s) {  if (error is FormatException) return s.errInvalidUsername;

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
