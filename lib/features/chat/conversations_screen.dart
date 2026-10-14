import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_settings_sheet.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

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

    return Scaffold(
      appBar: AppBar(
        title: Text(s.messages),
        actions: [
          const AppSettingsIconButton(),
          IconButton(
            tooltip: s.logOut,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
              } catch (error, stackTrace) {
                debugPrint('Unable to sign out: $error');
                debugPrintStack(stackTrace: stackTrace);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
              }
            },
          ),
          IconButton(
            tooltip: s.message,
            icon: const Icon(Icons.edit_square),
            onPressed: () async {
              final user = await showDialog<ChatUserPreview>(
                context: context,
                builder: (context) => _NewChatDialog(
                  repository: ref.read(chatRepositoryProvider),
                ),
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
            },
          ),
        ],
      ),
      body: conversations.when(
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

          return ListView.separated(
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
                          '${item.unreadCount}',
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
          );
        },
      ),
    );
  }
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog({required this.repository});

  final ChatRepository repository;

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _controller = TextEditingController();
  Future<List<ChatUserPreview>>? _results;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() {
      _results = value.trim().length < 2
          ? null
          : widget.repository.searchUsers(value);
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
