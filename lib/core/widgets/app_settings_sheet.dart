import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../l10n/locale_providers.dart';
import '../theme/theme_providers.dart';

Future<void> showAppSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const AppSettingsSheet(),
    );

/// Opens the sheet from an AppBar action.
class AppSettingsIconButton extends StatelessWidget {
  const AppSettingsIconButton({super.key, this.icon});

  /// Defaults to the gear icon; the home top bar passes a hamburger instead.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppStrings.of(context).settings,
      icon: Icon(icon ?? Icons.settings_outlined),
      onPressed: () => showAppSettingsSheet(context),
    );
  }
}

/// Opens the sheet from screens that have no AppBar, such as the auth screens.
class AppSettingsTextButton extends StatelessWidget {
  const AppSettingsTextButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showAppSettingsSheet(context),
      icon: const Icon(Icons.settings_outlined, size: 18),
      label: Text(AppStrings.of(context).settings),
    );
  }
}

class AppSettingsSheet extends ConsumerWidget {
  const AppSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeController = ref.read(localeControllerProvider.notifier);
    final themeController = ref.read(themeModeProvider.notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.settings,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Text(s.language, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _Choice(
                    label: s.followSystem,
                    selected: locale == null,
                    onTap: localeController.useSystemLocale,
                  ),
                  _Choice(
                    label: s.arabic,
                    selected: locale?.languageCode == 'ar',
                    onTap: () => localeController.setLocale(const Locale('ar')),
                  ),
                  _Choice(
                    label: s.english,
                    selected: locale?.languageCode == 'en',
                    onTap: () => localeController.setLocale(const Locale('en')),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(s.appearance, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _Choice(
                    label: s.followSystem,
                    icon: Icons.brightness_auto_outlined,
                    selected: themeMode == ThemeMode.system,
                    onTap: () => themeController.setMode(ThemeMode.system),
                  ),
                  _Choice(
                    label: s.lightMode,
                    icon: Icons.light_mode_outlined,
                    selected: themeMode == ThemeMode.light,
                    onTap: () => themeController.setMode(ThemeMode.light),
                  ),
                  _Choice(
                    label: s.darkMode,
                    icon: Icons.dark_mode_outlined,
                    selected: themeMode == ThemeMode.dark,
                    onTap: () => themeController.setMode(ThemeMode.dark),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 18),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
