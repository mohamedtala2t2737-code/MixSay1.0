import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/features/auth/presentation/screens/email_confirmation_screen.dart';
import 'package:social_chat/features/auth/presentation/screens/login_screen.dart';
import 'package:social_chat/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:social_chat/features/chat/chat_screen.dart';
import 'package:social_chat/features/chat/conversations_screen.dart';
import 'package:social_chat/features/home/presentation/main_shell.dart';
import 'package:social_chat/features/profile/presentation/follow_graph_screen.dart';
import 'package:social_chat/features/search/presentation/search_screen.dart';

/// Rebuilds the router whenever the Firebase auth state changes,
/// so the redirect below runs again after login / logout.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthRoute = switch (state.matchedLocation) {
      '/login' || '/signup' || '/check-email' => true,
      _ => false,
    };
    if (user == null) {
      return isAuthRoute ? null : '/login';
    }
    if (isAuthRoute) {
      return user.emailVerified ? '/home' : '/check-email';
    }
    final isStandaloneRoute =
        state.matchedLocation.startsWith('/chat/') ||
        const [
          '/conversations',
          '/search',
          '/followers',
          '/following',
        ].any(
          (path) =>
              state.matchedLocation == path ||
              state.matchedLocation.startsWith('$path/'),
        );
    return isStandaloneRoute || state.matchedLocation == '/home'
        ? null
        : '/home';
  },
  errorBuilder: (context, state) => Scaffold(
    body: ErrorStateView(
      message: AppStrings.of(context).loadFailed,
      onRetry: () => GoRouter.of(context).go('/home'),
    ),
  ),
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignUpScreen()),
    GoRoute(
      path: '/check-email',
      builder: (context, state) => const EmailConfirmationScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const MainShell()),
    GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
    GoRoute(
      path: '/conversations',
      builder: (context, state) => const ConversationsScreen(),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (context, state) =>
          ChatScreen(conversationId: state.pathParameters['conversationId']!),
    ),
    GoRoute(
      path: '/followers',
      builder: (context, state) => _followGraph(state, followers: true),
    ),
    GoRoute(
      path: '/following',
      builder: (context, state) => _followGraph(state, followers: false),
    ),
  ],
);

/// The follower or following list of an account. The profile screen names the
/// account it opened; without that the signed-in user's own list is meant.
FollowGraphScreen _followGraph(GoRouterState state, {required bool followers}) {
  return FollowGraphScreen(
    userId:
        state.uri.queryParameters['userId'] ??
        FirebaseAuth.instance.currentUser!.uid,
    followers: followers,
  );
}
