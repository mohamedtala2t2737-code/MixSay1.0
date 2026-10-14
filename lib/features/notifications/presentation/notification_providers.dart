import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/notifications/data/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>(
  (ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return Stream.error(StateError('Sign in to view notifications'));
    }
    return ref.watch(notificationRepositoryProvider).watchNotifications();
  },
);

/// Keeps the notification stream alive only while something is watching the
/// badge (the main shell), so signing out closes the Firestore listener.
final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value;
  if (notifications == null) return 0;
  return notifications.where((notification) => !notification.isRead).length;
});
