import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';

class PasswordStepView extends StatelessWidget {
  const PasswordStepView({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: AppStrings.of(context).password,
      controller: controller,
      errorText: errorText,
      helperText: AppStrings.of(context).passwordHint,
      obscure: true,
      textInputAction: TextInputAction.done,
      autofocus: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
