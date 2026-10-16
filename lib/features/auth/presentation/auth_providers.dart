import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/utils/age_group.dart';
import 'package:social_chat/features/auth/data/age_group_service.dart';
import 'package:social_chat/features/auth/data/firebase_auth_repository.dart';
import 'package:social_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_chat/features/auth/presentation/auth_controller.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final ageGroupServiceProvider = Provider<AgeGroupService>(
  (ref) => AgeGroupService(),
);

/// The signed-in user's id, or null when logged out.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateChangesProvider);
  return FirebaseAuth.instance.currentUser?.uid;
});

/// Fires on every login / logout / token refresh.
final authStateChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChanged,
);

/// The signed-in user's profile row. Refetched on every auth change.
final currentProfileProvider = FutureProvider.autoDispose<AppUser?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentProfile;
});

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

/// The signed-in user's age group, written to their own profile first if the
/// profile predates the field or has outgrown it. Runs again on every sign-in,
/// so a launch is what heals a legacy account.
final ageGroupProvider = FutureProvider<AgeGroup?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(ageGroupServiceProvider).resolve(userId);
});
