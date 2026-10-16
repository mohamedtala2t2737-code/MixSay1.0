import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// The app's yes/no prompt: a title, one line of consequences, and two answers.
///
/// Returns false when the user backs out — tapping the scrim counts as "no" — so
/// a caller only has to check one value.
Future<bool> askConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
}) async {
  final fallbackCancel = AppStrings.of(context).cancel;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel ?? fallbackCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed == true;
}
