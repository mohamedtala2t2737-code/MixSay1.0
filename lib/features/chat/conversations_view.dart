import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// The conversation list without a Scaffold, so it can be the shell's Messages
/// tab as well as the standalone `/conversations` route.
class ConversationsListView extends ConsumerWidget {
  const ConversationsListView({super.key});

  String _timeLabel(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final conversations = ref.watch(conversationsProvider);

    return conversations.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) {
        debugPrint('Unable to load conversations: $error');
        debugPrintStack(stackTrace: stackTrace);
        return ErrorStateView(
          message: s.loadFailed,
          onRetry: () => ref.invalidate(conversationsProvider),
        );
      },
      data: (items) {
        if (items.isEmpty) {
          return EmptyStateView(
            icon: Icons.chat_bubble_outline,
            title: s.noMessagesYet,
            subtitle: s.startConversation,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(conversationsProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final displayName = item.otherFullName.isEmpty
                  ? item.otherUsername
                  : item.otherFullName;
              return ListTile(
                leading: UserAvatar(
                  name: displayName,
                  url: item.otherAvatarUrl,
                  radius: 26,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (item.lastMessageAt != null)
                      Text(
                        _timeLabel(item.lastMessageAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                subtitle: Text(
                  item.lastMessageContent ?? s.noMessagesYet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: item.unreadCount > 0
                    ? CircleAvatar(
                        radius: 10,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          s.number(item.unreadCount),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
                onTap: () => context.push('/chat/${item.id}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// Asks who to message, opens (or creates) that conversation, and routes there.
Future<void> startNewChat(BuildContext context, WidgetRef ref) async {
  final s = AppStrings.of(context);
  final user = await showDialog<ChatUserPreview>(
    context: context,
    builder: (context) => const _NewChatDialog(),
  );
  if (user == null || !context.mounted) return;
  try {
    final conversationId = await ref
        .read(chatRepositoryProvider)
        .getOrCreateConversation(user.id);
    if (!context.mounted) return;
    context.push('/chat/$conversationId');
  } catch (error, stackTrace) {
    debugPrint('Unable to start conversation: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
  }
}

class _NewChatDialog extends ConsumerStatefulWidget {
  const _NewChatDialog();

  @override
  ConsumerState<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends ConsumerState<_NewChatDialog> {
  static const _debounceDuration = Duration(milliseconds: 350);

  final _controller = TextEditingController();
  Future<List<ChatUserPreview>>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// One query per pause in typing, not one per keystroke: every search is a
  /// billed range read on publicProfiles.
  void _search(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      setState(() {
        _results = ref.read(chatRepositoryProvider).searchUsers(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return AlertDialog(
      title: Text(s.message),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: s.searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _results == null
                  ? Center(child: Text(s.searchInitial))
                  : FutureBuilder<List<ChatUserPreview>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LoadingView();
                        }
                        if (snapshot.hasError) {
                          return ErrorStateView(message: s.loadFailed);
                        }
                        final users =
                            snapshot.data ?? const <ChatUserPreview>[];
                        if (users.isEmpty) {
                          return EmptyStateView(
                            icon: Icons.person_search_outlined,
                            title: s.noResults,
                          );
                        }
                        return ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final name = user.fullName.isEmpty
                                ? user.username
                                : user.fullName;
                            return ListTile(
                              leading: UserAvatar(
                                name: name,
                                url: user.avatarUrl,
                                radius: 20,
                              ),
                              title: Text(name),
                              subtitle: Text('@${user.username}'),
                              onTap: () => Navigator.of(context).pop(user),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
      ],
    );
  }
}
