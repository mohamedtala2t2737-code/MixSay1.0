import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/states.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_forward.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

/// The picker a forward is aimed with: the chats I already have, a search
/// through them, and the people I can open a new one with.
///
/// Rows are ticked rather than tapped because a forward usually goes to two or
/// three chats at once. A person with no chat yet is only *selected* here — the
/// conversation is created with the send, so closing the sheet without sending
/// leaves no empty thread behind.
class ChatForwardSheet extends ConsumerStatefulWidget {
  const ChatForwardSheet({super.key, required this.fromConversationId});

  /// The thread the message came from. Forwarding it back there would put a
  /// second copy where the original already sits, so it is not offered.
  final String fromConversationId;

  /// The chosen destinations, or null when the sheet was closed without
  /// sending.
  static Future<List<ChatForwardTarget>?> show(
    BuildContext context, {
    required String fromConversationId,
  }) => showModalBottomSheet<List<ChatForwardTarget>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        ChatForwardSheet(fromConversationId: fromConversationId),
  );

  @override
  ConsumerState<ChatForwardSheet> createState() => _ChatForwardSheetState();
}

class _ChatForwardSheetState extends ConsumerState<ChatForwardSheet> {
  static const _searchDebounce = Duration(milliseconds: 350);

  final _search = TextEditingController();
  final _selected = <ChatForwardTarget>{};
  Timer? _debounce;
  List<ChatUserPreview> _people = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // The chat rows filter locally, so every keystroke repaints; only the
    // people search waits for the typing to settle.
    setState(() {});
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _people = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(_searchDebounce, () => _searchPeople(query));
  }

  Future<void> _searchPeople(String query) async {
    try {
      final found = await ref.read(chatRepositoryProvider).searchUsers(query);
      if (!mounted) return;
      // A reply to a search the person has typed over by now is not a result
      // they asked for.
      if (query != _search.text.trim()) return;
      setState(() {
        _people = found;
        _searching = false;
      });
    } catch (_) {
      // People are the extra half of this search; the chats already on screen
      // keep answering even when Firestore cannot be reached.
      if (!mounted) return;
      setState(() {
        _people = const [];
        _searching = false;
      });
    }
  }

  void _toggle(ChatForwardTarget target) {
    setState(() {
      if (!_selected.remove(target)) _selected.add(target);
    });
  }

  void _send() {
    Navigator.of(context).pop(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final query = _search.text.trim().toLowerCase();
    final conversations = ref.watch(conversationsProvider);
    final chatIds = conversations.maybeWhen(
      data: (rows) => rows.map((row) => row.otherUserId).toSet(),
      orElse: () => const <String>{},
    );
    // A person already in my chats is chosen through that chat, not as a second
    // row that would open the same thread again.
    final newPeople = _people
        .where((person) => !chatIds.contains(person.id))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.forwardSheetTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty ? null : _send,
                    child: Text(strings.forwardSendTo(_selected.length)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: strings.forwardSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: strings.cancel,
                          onPressed: () {
                            _search.clear();
                            _onQueryChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.fieldFill(Theme.of(context).brightness),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                // Nine rows is what a phone screen shows at once; the list
                // scrolls inside that instead of filling the whole sheet.
                constraints: const BoxConstraints(maxHeight: 520),
                child: conversations.when(
                  loading: () => const LoadingView(),
                  error: (error, _) => ErrorStateView(
                    message: strings.noResults,
                    onRetry: () => ref.invalidate(conversationsProvider),
                    debugDetail: error.toString(),
                  ),
                  data: (rows) {
                    final chats = rows
                        .where((row) => row.id != widget.fromConversationId)
                        .where(
                          (row) =>
                              query.isEmpty ||
                              row.otherFullName.toLowerCase().contains(query) ||
                              row.otherUsername.toLowerCase().contains(query),
                        )
                        .toList();
                    if (chats.isEmpty && newPeople.isEmpty) {
                      return EmptyStateView(
                        icon: Icons.forward_to_inbox_outlined,
                        title: strings.noResults,
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final row in chats)
                          _TargetRow(
                            name: row.otherFullName.isEmpty
                                ? row.otherUsername
                                : row.otherFullName,
                            avatarUrl: row.otherAvatarUrl,
                            selected: _selected.contains(
                              ChatForwardTarget.conversation(row.id),
                            ),
                            onTap: () =>
                                _toggle(ChatForwardTarget.conversation(row.id)),
                          ),
                        if (newPeople.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              strings.forwardPeopleSection,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        for (final person in newPeople)
                          _TargetRow(
                            name: person.fullName.isEmpty
                                ? person.username
                                : person.fullName,
                            subtitle: '@${person.username}',
                            avatarUrl: person.avatarUrl,
                            selected: _selected.contains(
                              ChatForwardTarget.newChat(person.id),
                            ),
                            onTap: () =>
                                _toggle(ChatForwardTarget.newChat(person.id)),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tickable destination.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.name,
    required this.selected,
    required this.onTap,
    this.avatarUrl,
    this.subtitle,
  });

  final String name;
  final String? avatarUrl;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = subtitle;
    return ListTile(
      onTap: onTap,
      leading: UserAvatar(name: name, url: avatarUrl, radius: 20),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: selected ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      subtitle: detail == null
          ? null
          : Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      trailing: Checkbox(
        value: selected,
        onChanged: (_) => onTap(),
        shape: const CircleBorder(),
      ),
      selected: selected,
    );
  }
}
