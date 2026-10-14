import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';
import 'package:social_chat/core/widgets/mixsay_logo.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/auth/presentation/widgets/or_divider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref
        .read(authControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  Future<void> _showPasswordReset() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PasswordResetDialog(
        onSubmit: (email) => ref
            .read(authRepositoryProvider)
            .sendPasswordResetEmail(email: email),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Center(
                  child: MixSayLogo(
                    showIcon: false,
                    fontSize: 52,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.signupTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 36),
                AppTextField(
                  label: s.emailAddress,
                  icon: Icons.alternate_email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: s.password,
                  icon: Icons.lock_outline,
                  controller: _passwordController,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: authState.isLoading ? null : _showPasswordReset,
                    child: Text(s.forgotPassword),
                  ),
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _emailController,
                    _passwordController,
                  ]),
                  builder: (context, _) {
                    final canSubmit =
                        _emailController.text.trim().isNotEmpty &&
                        _passwordController.text.isNotEmpty;
                    return PrimaryButton(
                      label: s.logInButton,
                      loading: authState.isLoading,
                      onPressed: canSubmit ? _submit : null,
                    );
                  },
                ),
                const SizedBox(height: 28),
                OrDivider(label: s.or),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => context.go('/signup'),
                  child: Text.rich(
                    TextSpan(
                      text: '${s.noAccount} ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      children: [
                        TextSpan(
                          text: s.signUpLink,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: AppSettingsTextButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.onSubmit});

  final Future<void> Function(String email) onSubmit;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _emailController = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppStrings s) async {
    final email = _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = s.errInvalidEmail);
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      await widget.onSubmit(email);
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = describeAuthError(error, s));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.forgotPassword),
      content: _sent
          ? Text(s.resetLinkSent)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: s.emailAddress,
                  icon: Icons.alternate_email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _error,
                  autofillHints: const [AutofillHints.email],
                  autofocus: true,
                  onSubmitted: (_) => _submit(s),
                ),
                if (_sending)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        if (!_sent)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
        TextButton(
          onPressed: _sending
              ? null
              : () => _sent ? Navigator.of(context).pop() : _submit(s),
          child: Text(s.continueButton),
        ),
      ],
    );
  }
}
