import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/theme/app_radius.dart';
import 'package:social_chat/core/theme/app_spacing.dart';
import 'package:social_chat/core/theme/theme_providers.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/features/auth/presentation/sign_out_action.dart';
import 'package:social_chat/features/profile/presentation/coming_soon_screen.dart';
import 'package:social_chat/features/profile/presentation/widgets/settings_tile.dart';

/// Settings, laid out like the reference screen: a search field that filters
/// the rows below it, then blocks of rows under small grey headings.
///
/// Every row here points at something the app really has — the notification
/// list, the saved posts, the language and appearance switches, signing out.
/// The rows the app has no feature for are kept, because the reference design
/// keeps them, but they open a screen that says so.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String haystack) =>
      _query.isEmpty || haystack.toLowerCase().contains(_query.toLowerCase());

  Future<void> _pickFrom(
    BuildContext context, {
    required String title,
    required List<String> labels,
    required int selected,
    required ValueChanged<int> onPick,
  }) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => RadioGroup<int>(
        groupValue: selected,
        onChanged: (value) => Navigator.of(context).pop(value),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (var option = 0; option < labels.length; option++)
                RadioListTile<int>(value: option, title: Text(labels[option])),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
    if (index != null) onPick(index);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    final localeLabels = [s.followSystem, s.arabic, s.english];
    final localeIndex = locale == null
        ? 0
        : (locale.languageCode == 'ar' ? 1 : 2);
    final themeLabels = [s.followSystem, s.lightMode, s.darkMode];
    final themeIndex = switch (themeMode) {
      ThemeMode.system => 0,
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
    };

    final groups = <_SettingsGroup>[
      _SettingsGroup(
        title: s.yourAccountSection,
        items: [
          _SettingsItem(
            icon: Icons.person_outline,
            title: s.accountItem,
            subtitle: s.accountItemSubtitle,
            onTap: () => showComingSoon(context, title: s.accountItem),
          ),
          _SettingsItem(
            icon: Icons.translate,
            title: s.language,
            subtitle: s.languageItemSubtitle,
            value: localeLabels[localeIndex],
            onTap: () => _pickFrom(
              context,
              title: s.language,
              labels: localeLabels,
              selected: localeIndex,
              onPick: (index) {
                final controller = ref.read(localeControllerProvider.notifier);
                switch (index) {
                  case 1:
                    controller.setLocale(const Locale('ar'));
                  case 2:
                    controller.setLocale(const Locale('en'));
                  default:
                    controller.useSystemLocale();
                }
              },
            ),
          ),
          _SettingsItem(
            icon: Icons.brightness_6_outlined,
            title: s.appearance,
            subtitle: s.appearanceItemSubtitle,
            value: themeLabels[themeIndex],
            onTap: () => _pickFrom(
              context,
              title: s.appearance,
              labels: themeLabels,
              selected: themeIndex,
              onPick: (index) =>
                  ref.read(themeModeProvider.notifier).setMode(switch (index) {
                    1 => ThemeMode.light,
                    2 => ThemeMode.dark,
                    _ => ThemeMode.system,
                  }),
            ),
          ),
        ],
      ),
      _SettingsGroup(
        title: s.howYouUseSection,
        items: [
          _SettingsItem(
            icon: Icons.bookmark_outline,
            title: s.savedItem,
            onTap: () => context.push('/settings/saved'),
          ),
          _SettingsItem(
            icon: Icons.inventory_2_outlined,
            title: s.archiveItem,
            onTap: () => showComingSoon(context, title: s.archiveItem),
          ),
          _SettingsItem(
            icon: Icons.query_stats,
            title: s.yourActivityItem,
            onTap: () => showComingSoon(context, title: s.yourActivityItem),
          ),
          _SettingsItem(
            icon: Icons.notifications_none_rounded,
            title: s.notifications,
            subtitle: s.notificationsItemSubtitle,
            onTap: () => context.push('/settings/notifications'),
          ),
          _SettingsItem(
            icon: Icons.schedule,
            title: s.timeManagementItem,
            onTap: () => showComingSoon(context, title: s.timeManagementItem),
          ),
        ],
      ),
      _SettingsGroup(
        title: s.whoCanSeeSection,
        items: [
          _SettingsItem(
            icon: Icons.lock_outline,
            title: s.accountPrivacyItem,
            value: s.publicValue,
            onTap: () => showComingSoon(context, title: s.accountPrivacyItem),
          ),
          _SettingsItem(
            icon: Icons.block_outlined,
            title: s.blockedItem,
            onTap: () => showComingSoon(context, title: s.blockedItem),
          ),
        ],
      ),
      _SettingsGroup(
        title: s.supportSection,
        items: [
          _SettingsItem(
            icon: Icons.help_outline,
            title: s.helpItem,
            onTap: () => showComingSoon(context, title: s.helpItem),
          ),
          _SettingsItem(
            icon: Icons.info_outline,
            title: s.aboutItem,
            onTap: () => showComingSoon(context, title: s.aboutItem),
          ),
          _SettingsItem(
            icon: Icons.logout,
            title: s.logOut,
            onTap: () => confirmAndSignOut(context, ref),
          ),
        ],
      ),
    ];

    final visible = [
      for (final group in groups)
        (
          title: group.title,
          items: group.items
              .where(
                (item) =>
                    _matches(item.title) ||
                    (item.subtitle != null && _matches(item.subtitle!)),
              )
              .toList(growable: false),
        ),
    ].where((group) => group.items.isNotEmpty).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(s.settingsAndActivity)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: s.searchSettingsHint,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.mdBorder,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyStateView(
                    icon: Icons.search_off,
                    title: s.noSettingsMatches,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      for (final group in visible) ...[
                        SettingsSectionHeader(title: group.title),
                        for (final item in group.items)
                          SettingsTile(
                            icon: item.icon,
                            title: item.title,
                            subtitle: item.subtitle,
                            value: item.value,
                            onTap: item.onTap,
                          ),
                        const SettingsDivider(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;
}
