import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';

class BirthDateStepView extends StatelessWidget {
  const BirthDateStepView({
    super.key,
    required this.selectedDate,
    required this.onPick,
    this.errorText,
  });

  final DateTime? selectedDate;
  final VoidCallback onPick;
  final String? errorText;

  String _format(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPick,
          icon: Icon(
            Icons.cake_outlined,
            color: hasError ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          label: Text(
            selectedDate == null ? s.pickDate : _format(selectedDate!),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(
              color: hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorText!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
