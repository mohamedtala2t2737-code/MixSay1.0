import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';

class NameStepView extends StatelessWidget {
  const NameStepView({
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
      label: AppStrings.of(context).fullName,
      controller: controller,
      errorText: errorText,
      textInputAction: TextInputAction.next,
      autofocus: true,
      onChanged: onChanged,
    );
  }
}
