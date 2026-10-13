import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';

class EmailStepView extends StatelessWidget {
  const EmailStepView({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: AppStrings.of(context).email,
      controller: controller,
      errorText: errorText,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofocus: true,
      onChanged: onChanged,
    );
  }
}
