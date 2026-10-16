import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/confirmation_dialog.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';

/// Sign-out can be reached from the profile tab and the conversations app bar,
/// so the in-flight flag is file-wide: two taps on either button must not run
/// the repository sign-out (and the FCM token delete) twice.
bool _signOutInFlight = false;

Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  if (_signOutInFlight) return;
  final strings = AppStrings.of(context);
  final confirmed = await askConfirmation(
    context,
    title: strings.logOut,
    message: strings.logOutConfirm,
    confirmLabel: strings.logOut,
  );
  if (!confirmed) return;
  _signOutInFlight = true;
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (error, stackTrace) {
    debugPrint('Unable to sign out: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.actionFailed)));
  } finally {
    _signOutInFlight = false;
  }
}
