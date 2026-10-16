import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';

/// The screen every settings row with no backing feature opens. It says so in
/// the app's own chrome instead of showing data that does not exist.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: EmptyStateView(
          icon: Icons.build_outlined,
          title: s.comingSoon,
          subtitle: subtitle ?? s.comingSoonMessage,
        ),
      ),
    );
  }
}

/// Opens [ComingSoonScreen] on top of whatever is showing.
Future<void> showComingSoon(BuildContext context, {required String title}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ComingSoonScreen(title: title),
      ),
    );
