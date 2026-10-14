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

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value;
  if (notifications == null) return 0;
  return notifications.where((notification) => !notification.isRead).length;
});
