import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:social_chat/features/auth/presentation/screens/email_confirmation_screen.dart';
import 'package:social_chat/features/auth/presentation/screens/login_screen.dart';
import 'package:social_chat/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:social_chat/features/chat/chat_screen.dart';
import 'package:social_chat/features/chat/conversations_screen.dart';

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
      return user.emailVerified ? '/conversations' : '/check-email';
    }
    final isChatRoute =
        state.matchedLocation == '/conversations' ||
        state.matchedLocation.startsWith('/chat/');
    return isChatRoute ? null : '/conversations';
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignUpScreen()),
    GoRoute(
      path: '/check-email',
      builder: (context, state) => const EmailConfirmationScreen(),
    ),
    GoRoute(
      path: '/conversations',
      builder: (context, state) => const ConversationsScreen(),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (context, state) =>
          ChatScreen(conversationId: state.pathParameters['conversationId']!),
    ),
  ],
);
