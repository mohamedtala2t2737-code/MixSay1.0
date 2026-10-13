import 'package:social_chat/core/domain/app_user.dart';

import '../entities/auth_sign_up_outcome.dart';

abstract class AuthRepository {
  Stream<void> get onAuthStateChanged;

  /// Firebase Authentication accepts an email address, not a username.
  Future<void> signIn({required String email, required String password});

  Future<AuthSignUpOutcome> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required DateTime birthDate,
  });

  /// Case-insensitive check against the reserved usernames collection.
  Future<bool> isUsernameAvailable(String username);

  Future<void> resendEmailVerification();

  /// Sends Firebase's password-reset message to [email]; the account does not
  /// have to be signed in.
  Future<void> sendPasswordResetEmail({required String email});

  Future<bool> reloadEmailVerificationStatus();

  Future<void> signOut();

  /// The signed-in user's profile row, or null when logged out.
  Future<AppUser?> get currentProfile;
}
