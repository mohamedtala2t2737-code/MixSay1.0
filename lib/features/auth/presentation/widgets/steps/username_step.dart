import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/app_text_field.dart';
import 'package:social_chat/features/auth/domain/username_policy.dart';

/// Username input with a debounced, live availability check.
/// Reports the result up through [onAvailabilityChanged]:
/// null = unknown/checking, true = available, false = taken.
class UsernameStepView extends StatefulWidget {
  const UsernameStepView({
    super.key,
    required this.controller,
    required this.checkAvailability,
    required this.onAvailabilityChanged,
    this.errorText,
    this.checkErrorText,
    this.onChanged,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final Future<bool?> Function(String username) checkAvailability;
  final ValueChanged<bool?> onAvailabilityChanged;
  final String? errorText;
  final String? checkErrorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<UsernameStepView> createState() => _UsernameStepViewState();
}

class _UsernameStepViewState extends State<UsernameStepView> {
  Timer? _debounce;
  bool _checking = false;
  bool? _available;
  bool _checkFailed = false;
  int _checkGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onChanged?.call(value);
    _checkGeneration++;
    _debounce?.cancel();
    setState(() {
      _checking = false;
      _available = null;
      _checkFailed = false;
    });
    widget.onAvailabilityChanged(null);
    final trimmed = value.trim();
    if (!UsernamePolicy.isValid(trimmed)) return;
    _debounce = Timer(const Duration(milliseconds: 500), () => _check(trimmed));
  }

  Future<void> _check(String username) async {
    if (!mounted) return;
    final generation = ++_checkGeneration;
    setState(() => _checking = true);
    final result = await widget.checkAvailability(username);
    if (!mounted) return;
    if (generation != _checkGeneration ||
        widget.controller.text.trim() != username) {
      return;
    }
    setState(() {
      _checking = false;
      _checkFailed = result == null;
      _available = result;
    });
    widget.onAvailabilityChanged(_available);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    Widget? suffix;
    String? helper;
    Color? helperColor;
    if (_checking) {
      suffix = const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_available == true) {
      suffix = const Icon(Icons.check_circle, color: AppColors.success);
      helper = s.usernameAvailable;
      helperColor = AppColors.success;
    } else if (_available == false) {
      suffix = const Icon(Icons.cancel, color: AppColors.error);
      helper = s.usernameTaken;
      helperColor = AppColors.error;
    } else if (_checkFailed) {
      suffix = const Icon(Icons.error_outline, color: AppColors.error);
      helper = widget.checkErrorText ?? s.usernameCheckFailed;
      helperColor = AppColors.error;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: s.username,
          controller: widget.controller,
          helperText: s.usernameFormatHint,
          errorText: widget.errorText,
          maxLength: UsernamePolicy.maxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9.]')),
            TextInputFormatter.withFunction(
              (oldValue, newValue) => newValue.copyWith(
                text: newValue.text.toLowerCase(),
                composing: TextRange.empty,
              ),
            ),
          ],
          suffix: suffix,
          textInputAction: TextInputAction.next,
          autofocus: widget.autofocus,
          onChanged: _onChanged,
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, start: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    helper,
                    style: TextStyle(
                      color: helperColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_checkFailed)
                  TextButton(
                    onPressed: _checking
                        ? null
                        : () {
                            final username = widget.controller.text.trim();
                            if (UsernamePolicy.isValid(username)) {
                              _check(username);
                            }
                          },
                    child: Text(s.retry),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
