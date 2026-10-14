import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/notifications/chat_notification_service.dart';
import 'package:social_chat/features/auth/domain/entities/auth_sign_up_outcome.dart';
import 'package:social_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_chat/features/auth/domain/username_policy.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _publicProfiles =>
      _firestore.collection('publicProfiles');

  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  @override
  Stream<void> get onAuthStateChanged => _auth.authStateChanges().map((_) {});

  @override
  Future<void> signIn({required String email, required String password}) async {
    final trimmedEmail = email.trim();
    if (!trimmedEmail.contains('@')) {
      throw FirebaseAuthException(code: 'invalid-email');
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: trimmedEmail,
      password: password,
    );
    if (credential.user?.emailVerified != true) {
      throw const EmailNotConfirmedException();
    }
  }

  @override
  Future<AuthSignUpOutcome> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required DateTime birthDate,
  }) async {
    final normalizedUsername = UsernamePolicy.normalize(username);
    if (!UsernamePolicy.isValid(username)) {
      throw const FormatException('Invalid username format');
    }
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Firebase did not create the user');
    try {
      final usernameReference = _usernames.doc(normalizedUsername);
      final userReference = _users.doc(user.uid);
      await _firestore.runTransaction((transaction) async {
        final usernameSnapshot = await transaction.get(usernameReference);
        if (usernameSnapshot.exists) {
          throw const UsernameAlreadyTakenException();
        }
        transaction.set(usernameReference, {'uid': user.uid});
        transaction.set(userReference, {
          'birthDate': Timestamp.fromDate(
            DateTime.utc(birthDate.year, birthDate.month, birthDate.day),
          ),
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(_publicProfiles.doc(user.uid), {
          'id': user.uid,
          'username': username.trim(),
          'usernameLowercase': normalizedUsername,
          'fullName': fullName.trim(),
          'avatarUrl': null,
          'bio': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (error, stackTrace) {
      try {
        await user.delete();
      } catch (cleanupError, cleanupStackTrace) {
        debugPrint(
          'Unable to remove auth user after profile setup failed: '
          '$cleanupError',
        );
        debugPrintStack(stackTrace: cleanupStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    // Keep the new user signed in until the email is verified so the
    // confirmation screen can resend the link without asking for a password.
    await user.sendEmailVerification();
    return AuthSignUpOutcome.needsEmailConfirmation;
  }

  @override
  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in to resend the verification email');
    }
    await user.sendEmailVerification();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('An email address is required');
    }
    await _auth.sendPasswordResetEmail(email: trimmed);
  }

  @override
  Future<bool> reloadEmailVerificationStatus() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshedUser = _auth.currentUser;
    final isVerified = refreshedUser?.emailVerified ?? user.emailVerified;
    if (isVerified) await refreshedUser?.getIdToken(true);
    return isVerified;
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final normalized = UsernamePolicy.normalize(username);
    if (!UsernamePolicy.isValid(username)) {
      throw const FormatException('Invalid username format');
    }
    final claim = await _usernames
        .doc(normalized)
        .get(const GetOptions(source: Source.server));
    return !claim.exists;
  }

  @override
  Future<void> signOut() async {
    await ChatNotificationService.instance.unregisterForPush();
    await _auth.signOut();
  }

  @override
  Future<AppUser?> get currentProfile async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    final documents = await Future.wait([
      _users.doc(userId).get(),
      _publicProfiles.doc(userId).get(),
    ]);
    final privateData = documents[0].data();
    final publicData = documents[1].data();
    if (!documents[0].exists ||
        privateData == null ||
        !documents[1].exists ||
        publicData == null) {
      return null;
    }
    return AppUser.fromMap({
      ...publicData,
      ...privateData,
      'id': userId,
      'full_name': publicData['fullName'] ?? '',
      'avatar_url': publicData['avatarUrl'],
    });
  }
}
