import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/domain/entities/auth_sign_up_outcome.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';

/// Holds loading/error state for the auth screens.
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password),
    );
  }

  /// Returns null when sign-up failed; the error is then in [state]
  /// for the UI listeners to display.
  Future<AuthSignUpOutcome?> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required DateTime birthDate,
  }) async {
    state = const AsyncValue<void>.loading();
    AuthSignUpOutcome? outcome;
    final result = await AsyncValue.guard(() async {
      outcome = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: email,
            password: password,
            username: username,
            fullName: fullName,
            birthDate: birthDate,
          );
    });
    state = result;
    return result.hasError ? null : outcome;
  }

  Future<void> signOut() async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signOut(),
    );
  }
}
