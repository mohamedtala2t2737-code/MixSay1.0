import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/theme/app_typography.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';
import 'package:social_chat/features/chat/chat_time_labels.dart';
import 'package:social_chat/features/home/presentation/widgets/mixsay_bottom_bar.dart';

/// The conversation list without a Scaffold, so it can be the shell's Messages
/// tab as well as the standalone `/conversations` route.
class ConversationsListView extends ConsumerStatefulWidget {
  const ConversationsListView({super.key});

  @override
  ConsumerState<ConversationsListView> createState() =>
      _ConversationsListViewState();
}

class _ConversationsListViewState extends ConsumerState<ConversationsListView> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  String _query = '';
  List<ChatConversationPreview> _olderPages = const [];
  bool _loadingMore = false;

  /// Set once a page arrives shorter than the page size: everything the user
  /// has is already on screen and scrolling must stop asking.
  bool _atEnd = false;

  /// The oldest `lastMessageAt` on screen, which is where the next page starts.
  /// Set while building, read when the list hits its bottom.
  DateTime? _oldestLoadedAt;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Ask for the next page when the list is nearly at its end, so a user with
  /// hundreds of connections only ever pays for the ones they scroll to.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 240) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final before = _oldestLoadedAt;
    if (before == null || _loadingMore || _atEnd) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(chatRepositoryProvider)
          .fetchOlderConversations(before: before);
      if (!mounted) return;
      setState(() {
        _olderPages = [..._olderPages, ...page];
        // A short page is the last one; there is nothing older to ask for.
        if (page.length < ChatRepository.conversationPageSize) _atEnd = true;
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to load older conversations: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      // Leave the cursor alone: pulling to refresh or scrolling again retries.
      setState(() => _loadingMore = false);
    }
  }

  /// The rows to show: the live page plus anything older the user has scrolled
  /// to, with duplicates dropped and the search applied.
  List<ChatConversationPreview> _rows(List<ChatConversationPreview> livePage) {
    final merged = <String, ChatConversationPreview>{
      for (final item in [...livePage, ..._olderPages]) item.id: item,
    }.values.toList();
    merged.sort(
      (left, right) => (right.lastMessageAt ?? DateTime(0)).compareTo(
        left.lastMessageAt ?? DateTime(0),
      ),
    );
    _oldestLoadedAt = merged.isEmpty ? null : merged.last.lastMessageAt;
    if (_query.isEmpty) return merged;
    return merged
        .where(
          (item) =>
              item.otherFullName.toLowerCase().contains(_query) ||
              item.otherUsername.toLowerCase().contains(_query),
        )
        .toList();
  }

  /// Today gets a clock time; anything older gets the day, because "09:30" on a
  /// message from last month would read as if it had just arrived.
  String _whenLabel(DateTime? dateTime, AppStrings strings) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    if (chatIsSameDay(local, DateTime.now())) {
      return chatTimeLabel(strings, local);
    }
    return chatDateLabel(strings, local);
  }

  /// The last message, or the kind of thing it was when it carried no text.
  /// The type comes from the conversation document, so this costs no read.
  String _previewText(ChatConversationPreview item, AppStrings strings) {
    final content = item.lastMessageContent;
    if (content != null && content.isNotEmpty) return content;
    if (item.lastMessageAt == null) return strings.noMessagesYet;
    return item.lastMessageType.previewLabel(strings);
  }

  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    if (query == _query) return;
    setState(() => _query = query);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final conversations = ref.watch(conversationsProvider);

    return conversations.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) {
        debugPrint(
          'Unable to load conversations: ${describeFirestoreFailure(error)}',
        );
        debugPrintStack(stackTrace: stackTrace);
        return ErrorStateView(
          message: s.loadFailed,
          debugDetail: firestoreErrorCode(error),
          onRetry: () => ref.invalidate(conversationsProvider),
        );
      },
      data: (livePage) {
        if (livePage.isEmpty) {
          return EmptyStateView(
            icon: Icons.chat_bubble_outline,
            title: s.noMessagesYet,
            subtitle: s.startConversation,
          );
        }

        final rows = _rows(livePage);
        // The search field is row zero, a "nothing matches" note takes the
        // place of the rows, and a spinner sits under them while the next page
        // is in flight.
        final itemCount =
            1 + (rows.isEmpty ? 1 : rows.length) + (_loadingMore ? 1 : 0);

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _olderPages = const [];
              _atEnd = false;
            });
            ref.invalidate(conversationsProvider);
            await ref.read(conversationsProvider.future);
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // The transparent bottom bar overlays the list; this keeps the last
            // conversation reachable above it.
            padding: const EdgeInsets.only(bottom: MixSayBottomBar.barHeight),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _SearchField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onCleared: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                );
              }
              final row = index - 1;
              if (rows.isEmpty) {
                return EmptyStateView(
                  icon: Icons.search_off,
                  title: s.noResults,
                );
              }
              if (row >= rows.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final item = rows[row];
              final displayName = item.otherFullName.isEmpty
                  ? item.otherUsername
                  : item.otherFullName;
              final hasUnread = item.unreadCount > 0;
              final unreadStyle = TextStyle(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
              );
              return Column(
                children: [
                  ListTile(
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
                            style: unreadStyle,
                          ),
                        ),
                        if (item.lastMessageAt != null)
                          Text(
                            _whenLabel(item.lastMessageAt, s),
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      _previewText(item, s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: hasUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: hasUnread
                        ? CircleAvatar(
                            radius: 10,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
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
                  ),
                  if (row < rows.length - 1) const Divider(height: 1),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The row that filters the list by name. Searching is local to the rows that
/// are already loaded, so typing costs no Firestore read at all.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onCleared,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: s.searchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.close), onPressed: onCleared),
          filled: true,
          fillColor: AppColors.fieldFill(Theme.of(context).brightness),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Open (or create) the one-to-one thread with [userId] and route there. This
/// is what every "Message" button in the app calls.
///
/// A thread with yourself is refused here as well as by the repository, because
/// an entry point that appears on your own post or profile would otherwise open
/// a chat with nobody to read it.
Future<void> messageUser(
  BuildContext context,
  WidgetRef ref,
  String userId,
) async {
  final s = AppStrings.of(context);
  final me = ref.read(currentUserIdProvider);
  if (userId.isEmpty || userId == me) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.userUnavailable)));
    return;
  }
  try {
    final conversationId = await ref
        .read(chatRepositoryProvider)
        .getOrCreateConversation(userId);
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

/// Asks who to message, then opens that conversation.
Future<void> startNewChat(BuildContext context, WidgetRef ref) async {
  final user = await showDialog<ChatUserPreview>(
    context: context,
    builder: (context) => const _NewChatDialog(),
  );
  if (user == null || !context.mounted) return;
  await messageUser(context, ref, user.id);
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
    final screenSize = MediaQuery.sizeOf(context);
    // A fixed 420x280 box overflowed the dialog on narrow or landscape
    // screens, which clipped the search field and hid results off-screen.
    final dialogWidth = (screenSize.width - 96).clamp(240.0, 420.0);
    final resultsHeight = (screenSize.height * 0.45).clamp(96.0, 280.0);
    return AlertDialog(
      title: Text(s.message),
      content: SizedBox(
        width: dialogWidth,
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
              height: resultsHeight,
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
                          return ErrorStateView(
                            message: s.loadFailed,
                            debugDetail: firestoreErrorCode(snapshot.error),
                          );
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
