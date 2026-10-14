import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/conversations_view.dart';

/// Standalone conversation list route, kept for deep links and as the fallback
/// landing screen; the shell's Messages tab shows the same list.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.messages),
        actions: [
          const AppSettingsIconButton(),
          IconButton(
            tooltip: s.logOut,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
              } catch (error, stackTrace) {
                debugPrint('Unable to sign out: $error');
                debugPrintStack(stackTrace: stackTrace);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
              }
            },
          ),
          IconButton(
            tooltip: s.message,
            icon: const Icon(Icons.edit_square),
            onPressed: () => startNewChat(context, ref),
          ),
        ],
      ),
      body: const ConversationsListView(),
    );
  }
}
