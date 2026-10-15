import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/theme/app_typography.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/features/chat/conversations_view.dart';
import 'package:social_chat/features/home/presentation/create_post_sheet.dart';
import 'package:social_chat/features/home/presentation/home_tab.dart';
import 'package:social_chat/features/home/presentation/notifications_tab.dart';
import 'package:social_chat/features/home/presentation/widgets/mixsay_bottom_bar.dart';
import 'package:social_chat/features/notifications/presentation/notification_providers.dart';
import 'package:social_chat/features/profile/presentation/profile_screen.dart';

/// The four-tab shell: Home, Messages, Notifications, Profile, with a flat
/// bottom bar whose centre item opens the create-post sheet. Tab order mirrors
/// in RTL because every row inside reads the ambient [Directionality]; only
/// the home app bar is pinned, so menu and search keep their physical sides.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;

  /// The bar each tab shows above its content. The profile tab returns `null`
  /// because it paints its own account bar.
  PreferredSizeWidget? _buildAppBar(AppStrings s, BuildContext context) {
    final settings = AppSettingsIconButton(
      icon: _tab == 0 ? Icons.menu_rounded : null,
    );
    return switch (_tab) {
      0 => _PinnedAppBar(
        child: AppBar(
          centerTitle: true,
          title: const _MixSayWordmark(),
          leading: settings,
          actions: [
            IconButton(
              tooltip: s.search,
              icon: const Icon(Icons.search),
              onPressed: () => context.push('/search'),
            ),
          ],
        ),
      ),
      1 => AppBar(
        title: Text(s.messages),
        actions: [
          IconButton(
            tooltip: s.message,
            icon: const Icon(Icons.edit_square),
            onPressed: () => startNewChat(context, ref),
          ),
          settings,
        ],
      ),
      2 => AppBar(title: Text(s.notifications), actions: [settings]),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final unread = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      // The bar is transparent, so the tabs may run under it; each one leaves
      // MixSayBottomBar.barHeight of bottom clearance for the last row.
      extendBody: true,
      appBar: _buildAppBar(s, context),
      body: IndexedStack(
        index: _tab,
        children: const [
          HomeTab(),
          ConversationsListView(),
          NotificationsTab(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: MixSayBottomBar(
        currentIndex: _tab,
        unreadCount: unread,
        onSelect: (index) => setState(() => _tab = index),
        onCreate: () => showCreatePostSheet(context),
      ),
    );
  }
}

/// Pins the home bar to left-to-right so its slots keep their physical sides:
/// menu on the left edge, search on the right edge, in Arabic as well as
/// English. Only the bar is pinned — the body still mirrors with the language.
class _PinnedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PinnedAppBar({required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.ltr, child: child);
  }
}

/// Logo for the home bar, in Kalam: a print handwriting face, so the `M` and `S`
/// stay the typed capitals instead of script swashes. Latin letters, so it never
/// mirrors. No `height` is set on purpose — the face's own line box is 1.59 em,
/// 41 points at [AppTypography.wordmark], which is the tallest the 56-point
/// toolbar can hold without clipping the `y`.
class _MixSayWordmark extends StatelessWidget {
  const _MixSayWordmark();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ShaderMask(
        shaderCallback: (bounds) =>
            AppColors.brandGradient.createShader(bounds),
        child: const Text(
          'MixSay',
          style: TextStyle(
            fontFamily: 'Kalam',
            fontWeight: FontWeight.bold,
            fontSize: AppTypography.wordmark,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
