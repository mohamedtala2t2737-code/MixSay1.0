import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/home/presentation/notifications_tab.dart';

/// The notification list outside the shell, opened from the settings rows.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).notifications)),
      body: const NotificationsTab(),
    );
  }
}
