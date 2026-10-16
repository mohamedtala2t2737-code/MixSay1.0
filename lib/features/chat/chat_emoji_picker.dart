import 'package:flutter/material.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/l10n/app_strings.dart';

/// A Unicode emoji tray for the message field.
///
/// These are plain text characters, so nothing is uploaded and the receiver
/// needs no extra asset to read them. Picture packs are a different thing and
/// live behind [ChatFeatures.bundledStickers].
class ChatEmojiPicker extends StatelessWidget {
  const ChatEmojiPicker({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _frequentlyUsedGroups = <List<String>>[
    [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '😚',
      '😙',
    ],
    [
      '🤔',
      '🤗',
      '🤭',
      '🤫',
      '🤨',
      '😐',
      '😑',
      '😶',
      '😏',
      '😒',
      '🙄',
      '😬',
      '😮‍💨',
      '🤥',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
    ],
    [
      '🥳',
      '🥴',
      '🥺',
      '🤯',
      '🤠',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '😟',
      '🙁',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥵',
      '🥶',
      '😱',
      '😨',
      '😰',
    ],
    [
      '😢',
      '😭',
      '😤',
      '😠',
      '🤬',
      '😈',
      '👿',
      '💀',
      '☠️',
      '💩',
      '🤡',
      '👻',
      '👽',
      '😵',
      '😡',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🤧',
    ],
    [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💯',
      '✨',
    ],
    [
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '👏',
      '🙌',
      '🤝',
      '🙏',
      '💪',
      '👀',
      '🧠',
      '🫶',
      '🫡',
      '🤌',
      '☝️',
      '✋',
      '🖖',
    ],
    [
      '😅',
      '🫠',
      '🥲',
      '😇',
      '🤩',
      '🥹',
      '😋',
      '🤤',
      '🍕',
      '🍔',
      '☕',
      '🍺',
      '🎉',
      '🎊',
      '🎁',
      '🏆',
      '⚽',
      '🎮',
      '🎬',
      '🎵',
    ],
    [
      '🌙',
      '☀️',
      '🌧️',
      '⛅',
      '❄️',
      '🌈',
      '🔥',
      '⭐',
      '🌟',
      '💧',
      '🌸',
      '🌹',
      '🌻',
      '🌴',
      '🐱',
      '🐶',
      '🦁',
      '🐸',
      '🦋',
      '🐝',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!ChatFeatures.emojiPicker) return const SizedBox.shrink();
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, top: 6),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              AppStrings.of(context).emoji,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 168,
          child: GridView.count(
            crossAxisCount: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            children: [
              for (final group in _frequentlyUsedGroups)
                for (final emoji in group)
                  _EmojiButton(emoji: emoji, onSelected: onSelected),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onSelected});

  final String emoji;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelected(emoji),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
    );
  }
}
