import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/home/presentation/widgets/mixsay_bottom_bar.dart';
import 'package:social_chat/features/notifications/data/notification_repository.dart';
import 'package:social_chat/features/notifications/presentation/notification_providers.dart';

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  ({IconData icon, String Function(AppStrings) phrase}) _describe(
    AppStrings s,
    String type,
  ) {
    return switch (type) {
      'like' => (icon: Icons.favorite_rounded, phrase: (s) => s.notifLike),
      'comment' => (
        icon: Icons.mode_comment_outlined,
        phrase: (s) => s.notifComment,
      ),
      'message' => (
        icon: Icons.mail_outline_rounded,
        phrase: (s) => s.notifMessage,
      ),
      'follow' => (icon: Icons.person_add_alt_1, phrase: (s) => s.notifFollow),
      _ => (
        icon: Icons.notifications_none_rounded,
        phrase: (s) => s.notifGeneric,
      ),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final notifications = ref.watch(notificationsProvider);
    final items = notifications.value ?? const <AppNotification>[];

    Widget? status;
    if (notifications.hasError) {
      debugPrint('Unable to load notifications: ${notifications.error}');
      status = ErrorStateView(
        message: s.loadFailed,
        onRetry: () => ref.invalidate(notificationsProvider),
      );
    } else if (notifications.isLoading && items.isEmpty) {
      status = const LoadingView();
    }

    return Column(
      children: [
        if (items.any((item) => !item.isRead))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    await ref
                        .read(notificationRepositoryProvider)
                        .markAllRead(items);
                  } catch (error, stackTrace) {
                    debugPrint('Unable to mark notifications read: $error');
                    debugPrintStack(stackTrace: stackTrace);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
                  }
                },
                icon: const Icon(Icons.done_all_rounded),
                label: Text(s.markAllRead),
              ),
            ),
          ),
        Expanded(
          child:
              status ??
              (items.isEmpty
                  ? EmptyStateView(
                      icon: Icons.notifications_none_rounded,
                      title: s.noNotifications,
                    )
                  : ListView.separated(
                      // Clearance for the transparent bottom bar.
                      padding: const EdgeInsets.only(
                        bottom: MixSayBottomBar.barHeight,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final kind = _describe(s, item.type);
                        final created = item.createdAt;
                        return ListTile(
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              UserAvatar(name: item.actorName, radius: 21),
                              if (!item.isRead)
                                PositionedDirectional(
                                  top: 0,
                                  end: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.colorScheme.surface,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            '${item.actorName} ${kind.phrase(s)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: created == null
                              ? null
                              : Text(timeAgo(created, isArabic: s.isArabic)),
                          trailing: Icon(
                            kind.icon,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          onTap: () {
                            if (!item.isRead) {
                              ref
                                  .read(notificationRepositoryProvider)
                                  .markRead(item.id)
                                  .catchError((Object error) {
                                    debugPrint(
                                      'Unable to mark a notification read: $error',
                                    );
                                  });
                            }
                            final conversationId = item.conversationId;
                            if (conversationId != null &&
                                conversationId.isNotEmpty) {
                              context.push('/chat/$conversationId');
                            }
                          },
                        );
                      },
                    )),
        ),
      ],
    );
  }
}
