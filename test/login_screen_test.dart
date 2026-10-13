import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/auth/domain/entities/auth_sign_up_outcome.dart';
import 'package:social_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('sends a password reset email from the login screen', (
    tester,
  ) async {
    final repository = _TestAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MixSay'), findsOneWidget);
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'alex@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.resetEmail, 'alex@example.com');
    expect(
      find.text('A password reset link has been sent to your email.'),
      findsOneWidget,
    );
  });
}

class _TestAuthRepository implements AuthRepository {
  String? resetEmail;

  @override
  Stream<void> get onAuthStateChanged => const Stream<void>.empty();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetEmail = email;
  }

  @override
  Future<AuthSignUpOutcome> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required DateTime birthDate,
  }) async => AuthSignUpOutcome.needsEmailConfirmation;

  @override
  Future<bool> isUsernameAvailable(String username) async => true;

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<bool> reloadEmailVerificationStatus() async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<AppUser?> get currentProfile async => null;
}
