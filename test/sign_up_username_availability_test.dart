import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/domain/app_user.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/auth/domain/entities/auth_sign_up_outcome.dart';
import 'package:social_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:social_chat/features/auth/presentation/widgets/steps/username_step.dart';

void main() {
  testWidgets('renders the signup form in Arabic RTL', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('ar'),
          localizationsDelegates: [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: SignUpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    expect(find.text('الاسم بالكامل'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(SignUpScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets('creates a Firebase account from the complete signup form', (
    tester,
  ) async {
    final repository = _AvailableUsernameRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: const SignUpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a new account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Alex Smith');
    await tester.enterText(fields.at(1), 'alex@example.com');
    await tester.enterText(fields.at(2), 'alex.123');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(3), 'Password123');
    await tester.enterText(fields.at(4), 'Password123');

    final dropdowns = find.byType(DropdownButtonFormField<int>);
    await _selectDropdownValue(
      tester,
      dropdowns,
      2,
      (DateTime.now().year - 20).toString(),
    );
    await _selectDropdownValue(tester, dropdowns, 1, 'January');
    await _selectDropdownValue(tester, dropdowns, 0, '1');

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(repository.signUpCalls, 1);
    expect(repository.createdFullName, 'Alex Smith');
    expect(repository.createdUsername, 'alex.123');
    expect(
      repository.createdBirthDate,
      DateTime(DateTime.now().year - 20, 1, 1),
    );
  });

  testWidgets('blocks account creation for a birthday younger than 13', (
    tester,
  ) async {
    final repository = _AvailableUsernameRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: const SignUpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Alex Smith');
    await tester.enterText(fields.at(1), 'alex@example.com');
    await tester.enterText(fields.at(2), 'alex.123');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(3), 'Password123');
    await tester.enterText(fields.at(4), 'Password123');

    final dropdowns = find.byType(DropdownButtonFormField<int>);
    await _selectDropdownValue(
      tester,
      dropdowns,
      2,
      (DateTime.now().year - 12).toString(),
    );
    await _selectDropdownValue(tester, dropdowns, 1, 'January');
    await _selectDropdownValue(tester, dropdowns, 0, '1');

    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('You must be at least 13.'), findsOneWidget);
    expect(repository.signUpCalls, 0);
  });

  testWidgets('scrolls back to the first field that failed validation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AvailableUsernameRepo()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: const SignUpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Start at the bottom, where the submit button lives, so a rejected submit
    // has to move the viewport back up to the name field on its own.
    double pageOffset() =>
        Scrollable.of(tester.element(find.text('Create account')))
            .position
            .pixels;

    await tester.ensureVisible(find.text('Create account'));
    await tester.pumpAndSettle();
    final bottomOffset = pageOffset();
    expect(bottomOffset, greaterThan(0));

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(pageOffset(), lessThan(bottomOffset));
    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets(
    'shows a retry after lookup failure and accepts a successful retry',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var attempts = 0;
      bool? availability;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: UsernameStepView(
              controller: controller,
              checkAvailability: (_) async {
                attempts += 1;
                return attempts == 1 ? null : true;
              },
              onAvailabilityChanged: (value) => availability = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'alex.123');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Could not check, try again'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(availability, isTrue);
      expect(find.text('Username is available'), findsOneWidget);
    },
  );

  testWidgets('ignores stale username lookup results', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final requests = <Completer<bool?>>[];
    bool? availability;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: UsernameStepView(
            controller: controller,
            checkAvailability: (_) {
              final request = Completer<bool?>();
              requests.add(request);
              return request.future;
            },
            onAvailabilityChanged: (value) => availability = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'older.1');
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests, hasLength(1));

    await tester.enterText(find.byType(TextField), 'newer.1');
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests, hasLength(2));

    requests[1].complete(true);
    await tester.pumpAndSettle();
    expect(availability, isTrue);

    requests[0].complete(false);
    await tester.pumpAndSettle();
    expect(availability, isTrue);
    expect(find.text('Username is available'), findsOneWidget);
  });

  testWidgets('lowercases usernames and filters unsupported characters', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: UsernameStepView(
            controller: controller,
            checkAvailability: (_) async => true,
            onAvailabilityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Mix_Say-24.');

    expect(controller.text, 'mixsay24.');
  });
}

Future<void> _selectDropdownValue(
  WidgetTester tester,
  Finder dropdowns,
  int index,
  String value,
) async {
  await tester.ensureVisible(dropdowns.at(index));
  await tester.pumpAndSettle();
  await tester.tap(dropdowns.at(index));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(value),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

class _AvailableUsernameRepo implements AuthRepository {
  int signUpCalls = 0;
  String? createdFullName;
  String? createdUsername;
  DateTime? createdBirthDate;

  @override
  Stream<void> get onAuthStateChanged => const Stream<void>.empty();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<AuthSignUpOutcome> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
    required DateTime birthDate,
  }) async {
    signUpCalls++;
    createdFullName = fullName;
    createdUsername = username;
    createdBirthDate = birthDate;
    return AuthSignUpOutcome.loggedIn;
  }

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
