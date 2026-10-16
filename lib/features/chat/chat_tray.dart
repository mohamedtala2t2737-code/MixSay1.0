import 'package:flutter/material.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/config/chat_secrets.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_emoji_picker.dart';
import 'package:social_chat/features/chat/chat_gif_search.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';

/// What the panel under the composer can show.
///
/// There is no "Saved" tab yet: saving a sticker is Phase 3, and a star tab with
/// nothing behind it is exactly the dead control this app keeps off screen.
enum ChatTrayTab { emoji, stickers, gif }

/// The panel that takes the keyboard's place. One tab bar, one body, and a tab
/// only appears when tapping it really produces something.
class ChatTray extends StatefulWidget {
  const ChatTray({
    super.key,
    required this.initial,
    required this.onEmoji,
    required this.onSticker,
    this.onGif,
    this.onTabChanged,
    this.tabs,
  });

  final ChatTrayTab initial;
  final ValueChanged<String> onEmoji;
  final ValueChanged<String> onSticker;

  /// Only called for the GIF tab, which [availableTabs] only lists when the
  /// search really has a key to search with.
  final ValueChanged<ChatGif>? onGif;

  /// Which tab the sender moved to, so the panel comes back to the same place
  /// after a trip to the keyboard.
  final ValueChanged<ChatTrayTab>? onTabChanged;

  /// Replaced in tests; production uses [availableTabs].
  final List<ChatTrayTab>? tabs;

  /// The tabs the flags of this build allow. A search that cannot reach Tenor
  /// is not offered as a tab, and a sticker type the plan cannot store does not
  /// appear either.
  static List<ChatTrayTab> availableTabs() => [
    if (ChatFeatures.emojiPicker) ChatTrayTab.emoji,
    if (!ChatMessageType.sticker.isGated) ChatTrayTab.stickers,
    if (ChatFeatures.gifSearch && ChatSecrets.hasTenorKey) ChatTrayTab.gif,
  ];

  @override
  State<ChatTray> createState() => _ChatTrayState();
}

class _ChatTrayState extends State<ChatTray> with TickerProviderStateMixin {
  late final List<ChatTrayTab> _tabs = widget.tabs ?? ChatTray.availableTabs();

  /// The panel opens on the tab the composer button chose, or on the first one
  /// this build has when that tab is not on offer.
  late final TabController? _controller = _tabs.isEmpty
      ? null
      : TabController(
          length: _tabs.length,
          initialIndex: _tabs
              .indexOf(widget.initial)
              .clamp(0, _tabs.length - 1),
          vsync: this,
        );

  @override
  void initState() {
    super.initState();
    _controller?.addListener(_reportTab);
  }

  /// The tab only counts as chosen once the slide has settled, so a swipe that
  /// bounces back does not move the panel.
  void _reportTab() {
    final controller = _controller;
    if (controller == null || controller.indexIsChanging) return;
    widget.onTabChanged?.call(_tabs[controller.index]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _label(ChatTrayTab tab, AppStrings strings) => switch (tab) {
    ChatTrayTab.emoji => strings.emoji,
    ChatTrayTab.stickers => strings.stickers,
    ChatTrayTab.gif => strings.attachGif,
  };

  Widget _body(ChatTrayTab tab) => switch (tab) {
    ChatTrayTab.emoji => ChatEmojiPicker(onSelected: widget.onEmoji),
    ChatTrayTab.stickers => ChatStickerPicker(onSelected: widget.onSticker),
    ChatTrayTab.gif => ChatGifPicker(
      onSelected: (gif) => widget.onGif?.call(gif),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final tabs = _tabs;
    final controller = _controller;
    if (tabs.isEmpty || controller == null) return const SizedBox.shrink();
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in tabs)
              Tab(
                height: 40,
                child: Text(
                  _label(tab, strings),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 228,
          child: TabBarView(
            controller: controller,
            children: [for (final tab in tabs) _body(tab)],
          ),
        ),
      ],
    );
  }
}
