import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';

class EmailConfirmationScreen extends ConsumerStatefulWidget {
  const EmailConfirmationScreen({super.key});

  @override
  ConsumerState<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState
    extends ConsumerState<EmailConfirmationScreen> {
  static const _resendCooldownSeconds = 60;
  static const _resendCooldown = Duration(seconds: _resendCooldownSeconds);

  Timer? _cooldownTimer;
  int _secondsRemaining = 0;
  bool _sending = false;
  bool _checking = false;
  bool _restoringCooldown = true;

  User? get _user => FirebaseAuth.instance.currentUser;

  String? get _cooldownKey {
    final uid = _user?.uid;
    return uid == null ? null : 'email_verification_resend_until_$uid';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCooldown());
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreCooldown() async {
    final key = _cooldownKey;
    try {
      if (key != null) {
        final preferences = await SharedPreferences.getInstance();
        final untilMillis = preferences.getInt(key);
        if (untilMillis != null) {
          final seconds = DateTime.fromMillisecondsSinceEpoch(untilMillis)
              .difference(DateTime.now())
              .inSeconds;
          final remaining = seconds.clamp(0, _resendCooldownSeconds);
          if (remaining > 0 && mounted) _startCooldown(remaining);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to restore email verification cooldown: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _restoringCooldown = false);
    }
  }

  void _startCooldown([int seconds = _resendCooldownSeconds]) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _secondsRemaining = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining -= 1);
    });
  }

  Future<void> _resendVerification() async {
    if (_sending || _secondsRemaining > 0 || _user == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).resendEmailVerification();
      final key = _cooldownKey;
      if (mounted) _startCooldown();
      if (key != null) {
        final until = DateTime.now()
            .add(_resendCooldown)
            .millisecondsSinceEpoch;
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setInt(key, until);
        } catch (error, stackTrace) {
          debugPrint('Unable to persist email verification cooldown: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).verificationEmailSent)),
        );
    } catch (error, stackTrace) {
      debugPrint('Unable to resend email verification: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(describeAuthError(error, AppStrings.of(context))),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerification() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final verified = await ref
          .read(authRepositoryProvider)
          .reloadEmailVerificationStatus();
      if (!mounted) return;
      if (verified) {
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(AppStrings.of(context).emailNotVerifiedYet)),
          );
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to refresh email verification status: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).verificationStatusFailed),
          ),
        );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _backToLogin() async {
    if (_user != null) {
      try {
        await ref.read(authRepositoryProvider).signOut();
      } catch (error, stackTrace) {
        debugPrint('Unable to sign out from email confirmation: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(describeAuthError(error, AppStrings.of(context))),
            ),
          );
        return;
      }
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final user = _user;
    final resendLabel = _secondsRemaining > 0
        ? s.verificationResendCooldown(_secondsRemaining)
        : s.resendVerification;

    return Scaffold(
      appBar: AppBar(title: Text(s.checkEmailTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(s.checkEmailTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(s.checkEmailBody, textAlign: TextAlign.center),
              if (user?.email case final email?) ...[
                const SizedBox(height: 8),
                SelectableText(
                  email,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: s.checkVerification,
                loading: _checking,
                onPressed: user == null ? null : _checkVerification,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed:
                    user == null ||
                        _restoringCooldown ||
                        _sending ||
                        _secondsRemaining > 0
                    ? null
                    : _resendVerification,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(resendLabel),
              ),
              if (user == null) ...[
                const SizedBox(height: 12),
                Text(
                  s.signInToResendVerification,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextButton(onPressed: _backToLogin, child: Text(s.backToLogin)),
            ],
          ),
        ),
      ),
    );
  }
}
