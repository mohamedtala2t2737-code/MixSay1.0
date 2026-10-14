import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';
import 'package:social_chat/core/widgets/mixsay_logo.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/features/auth/domain/entities/auth_sign_up_outcome.dart';
import 'package:social_chat/features/auth/domain/username_policy.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/auth/presentation/widgets/steps/username_step.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameAvailabilityListenable = ValueNotifier<bool?>(null);

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final Map<String, String> _errors = {};
  int? _birthDay;
  int? _birthMonth;
  int? _birthYear;
  String? _usernameCheckErrorText;
  bool? _usernameAvailable;

  DateTime? get _birthDate {
    final day = _birthDay;
    final month = _birthMonth;
    final year = _birthYear;
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameAvailabilityListenable.dispose();
    super.dispose();
  }

  bool _isAtLeastThirteen(DateTime birthday) {
    final eligibleDate = DateTime.utc(
      birthday.year + 13,
      birthday.month,
      birthday.day,
    );
    return !DateTime.now().toUtc().isBefore(eligibleDate);
  }

  bool _validateForm() {
    final s = AppStrings.of(context);
    final errors = <String, String>{};
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final birthday = _birthDate;

    if (fullName.isEmpty) {
      errors['fullName'] = s.errRequired;
    } else if (fullName.length < 2) {
      errors['fullName'] = s.errNameTooShort;
    }
    if (email.isEmpty) {
      errors['email'] = s.errRequired;
    } else if (!_emailRegex.hasMatch(email)) {
      errors['email'] = s.errInvalidEmail;
    }
    if (!UsernamePolicy.isValid(username)) {
      errors['username'] = s.errInvalidUsername;
    } else if (_usernameAvailable == false) {
      errors['username'] = s.usernameTaken;
    } else if (_usernameAvailable != true) {
      errors['username'] = _usernameCheckErrorText ?? s.usernameCheckFailed;
    }
    if (_passwordController.text.isEmpty) {
      errors['password'] = s.errRequired;
    } else if (_passwordController.text.length < 8) {
      errors['password'] = s.errPasswordTooShort;
    }
    if (_confirmPasswordController.text.isEmpty) {
      errors['confirmPassword'] = s.errRequired;
    } else if (_confirmPasswordController.text != _passwordController.text) {
      errors['confirmPassword'] = s.errPasswordMismatch;
    }
    if (birthday == null) {
      errors['birthDate'] = s.errRequired;
    } else if (!_isAtLeastThirteen(birthday)) {
      errors['birthDate'] = s.ageError;
    }

    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  Future<void> _submit() async {
    if (!_validateForm()) return;

    final outcome = await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim(),
          fullName: _fullNameController.text.trim(),
          birthDate: _birthDate!,
        );
    if (!mounted) return;
    if (outcome == AuthSignUpOutcome.needsEmailConfirmation) {
      context.go('/check-email');
    }
  }

  void _onBirthDateChanged({int? day, int? month, int? year}) {
    setState(() {
      if (day != null) _birthDay = day;
      if (month != null) _birthMonth = month;
      if (year != null) _birthYear = year;

      final selectedMonth = _birthMonth;
      if (selectedMonth != null && _birthDay != null) {
        final selectedYear = _birthYear ?? 2000;
        final lastDay = DateTime(selectedYear, selectedMonth + 1, 0).day;
        if (_birthDay! > lastDay) _birthDay = lastDay;
      }
      _errors.remove('birthDate');
    });
  }

  Future<bool?> _checkUsernameAvailability(String username) async {
    try {
      final available = await ref
          .read(authRepositoryProvider)
          .isUsernameAvailable(username);
      _usernameCheckErrorText = null;
      return available;
    } catch (error, stackTrace) {
      if (error is FirebaseException) {
        debugPrint(
          'Username availability FirebaseException: '
          'plugin=${error.plugin}, code=${error.code}, '
          'message=${error.message ?? '(no message)'}',
        );
      } else {
        debugPrint(
          'Username availability error '
          '(${error.runtimeType}): $error',
        );
      }
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _usernameCheckErrorText = describeUsernameCheckError(
            error,
            AppStrings.of(context),
          );
        });
      }
      return null;
    }
  }

  void _clearError(String field) {
    if (_errors.containsKey(field) ||
        (field == 'username' && _usernameCheckErrorText != null)) {
      setState(() {
        _errors.remove(field);
        if (field == 'username') _usernameCheckErrorText = null;
      });
    }
  }

  Widget _buildDateDropdown({
    required String label,
    required int? value,
    required List<int> values,
    required ValueChanged<int?> onChanged,
  }) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.fieldFill(theme.brightness),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<int>(
              value: item,
              child: Text(item.toString()),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildBirthdayFields(AppStrings s) {
    final year = _birthYear ?? 2000;
    final month = _birthMonth;
    final daysInMonth = month == null ? 31 : DateTime(year, month + 1, 0).day;
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.birthDate,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDateDropdown(
                label: s.day,
                value: _birthDay,
                values: List<int>.generate(daysInMonth, (index) => index + 1),
                onChanged: (value) {
                  if (value != null) _onBirthDateChanged(day: value);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                initialValue: _birthMonth,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.month,
                  filled: true,
                  fillColor: AppColors.fieldFill(Theme.of(context).brightness),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outline
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  s.birthMonths.length,
                  (index) => DropdownMenuItem<int>(
                    value: index + 1,
                    child: Text(s.birthMonths[index]),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) _onBirthDateChanged(month: value);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDateDropdown(
                label: s.year,
                value: _birthYear,
                values: List<int>.generate(
                  today.year - 1900 + 1,
                  (index) => today.year - index,
                ),
                onChanged: (value) {
                  if (value != null) _onBirthDateChanged(year: value);
                },
              ),
            ),
          ],
        ),
        if (_errors['birthDate'] case final error?)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8, start: 12),
            child: Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          s.birthDatePrivacyNote,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);

    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(describeAuthError(next.error!, s))),
          );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppSettingsTextButton(),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: MixSayLogo(
                      showIcon: false,
                      fontSize: 46,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.signUpTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.signupTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 26),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      _fullNameController,
                      _emailController,
                      _usernameController,
                      _passwordController,
                      _confirmPasswordController,
                      _usernameAvailabilityListenable,
                    ]),
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: s.fullName,
                          icon: Icons.person_outline,
                          controller: _fullNameController,
                          errorText: _errors['fullName'],
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          onChanged: (_) => _clearError('fullName'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: s.email,
                          icon: Icons.mail_outline,
                          controller: _emailController,
                          errorText: _errors['email'],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          onChanged: (_) => _clearError('email'),
                        ),
                        const SizedBox(height: 12),
                        UsernameStepView(
                          controller: _usernameController,
                          autofocus: false,
                          errorText: _usernameAvailable == false
                              ? null
                              : _errors['username'],
                          checkErrorText: _usernameCheckErrorText,
                          checkAvailability: _checkUsernameAvailability,
                          onAvailabilityChanged: (available) {
                            setState(() {
                              _usernameAvailable = available;
                              if (available != null) {
                                _errors.remove('username');
                              }
                            });
                            _usernameAvailabilityListenable.value = available;
                          },
                          onChanged: (_) => _clearError('username'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: s.password,
                          icon: Icons.lock_outline,
                          controller: _passwordController,
                          errorText: _errors['password'],
                          helperText: s.passwordHint,
                          obscure: true,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => _clearError('password'),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: s.confirmPassword,
                          icon: Icons.lock_reset_outlined,
                          controller: _confirmPasswordController,
                          errorText: _errors['confirmPassword'],
                          obscure: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) => _clearError('confirmPassword'),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        _buildBirthdayFields(s),
                        const SizedBox(height: 20),
                        PrimaryButton(
                          label: s.createAccount,
                          loading: authState.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s.alreadyHaveAccount,
                              style: theme.textTheme.bodyMedium,
                            ),
                            TextButton(
                              onPressed: () => context.go('/login'),
                              child: Text(s.logInButton),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
