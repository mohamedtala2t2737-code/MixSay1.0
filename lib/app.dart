import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/notifications/chat_notification_service.dart';
import 'package:social_chat/core/router/app_router.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/core/theme/theme_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/splash/presentation/splash_gate.dart';

class SocialChatApp extends ConsumerStatefulWidget {
  const SocialChatApp({super.key});

  @override
  ConsumerState<SocialChatApp> createState() => _SocialChatAppState();
}

class _SocialChatAppState extends ConsumerState<SocialChatApp> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(localeControllerProvider.notifier).restore());
    unawaited(ref.read(themeModeProvider.notifier).restore());
    unawaited(ref.read(savedPostsProvider.notifier).restore());
    unawaited(
      ChatNotificationService.instance.initialize(
        chatRepository: ref.read(chatRepositoryProvider),
        onOpenConversation: (conversationId) async =>
            appRouter.push('/chat/$conversationId'),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(ChatNotificationService.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MixSay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeControllerProvider),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
      builder: (context, child) =>
          SplashGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
