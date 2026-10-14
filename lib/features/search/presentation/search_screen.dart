import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// Username search reached from the home top bar; tapping a result opens (or
/// creates) a conversation with that person.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
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
          : ref.read(chatRepositoryProvider).searchUsers(value);
    });
  }

  Future<void> _openChat(ChatUserPreview user) async {
    final s = AppStrings.of(context);
    try {
      final conversationId = await ref
          .read(chatRepositoryProvider)
          .getOrCreateConversation(user.id);
      if (!mounted) return;
      context.push('/chat/$conversationId');
    } catch (error, stackTrace) {
      debugPrint('Unable to start conversation: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: s.searchHint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      body: _results == null
          ? EmptyStateView(
              icon: Icons.person_search_outlined,
              title: s.searchInitial,
            )
          : FutureBuilder<List<ChatUserPreview>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                if (snapshot.hasError) {
                  debugPrint('Unable to search users: ${snapshot.error}');
                  return ErrorStateView(message: s.loadFailed);
                }
                final users = snapshot.data ?? const <ChatUserPreview>[];
                if (users.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.person_search_outlined,
                    title: s.noResults,
                  );
                }
                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final name = user.fullName.isEmpty
                        ? user.username
                        : user.fullName;
                    return ListTile(
                      leading: UserAvatar(
                        name: name,
                        url: user.avatarUrl,
                        radius: 22,
                      ),
                      title: Text(name),
                      subtitle: Text('@${user.username}'),
                      onTap: () => _openChat(user),
                    );
                  },
                );
              },
            ),
    );
  }
}
