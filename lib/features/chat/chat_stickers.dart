import 'package:flutter/material.dart';

import 'package:social_chat/core/l10n/app_strings.dart';

/// One picture pack shipped inside the app.
///
/// A sent sticker is only the id string [chatStickerId] builds, so the receiver
/// needs the same asset and nothing else: no upload, no Storage object, and no
/// field that `firestore.rules` has never heard of.
class ChatStickerPack {
  const ChatStickerPack({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.stickers,
  });

  /// The folder name under `assets/stickers/`, and the first half of an id.
  final String id;

  final String nameAr;
  final String nameEn;

  /// File names in the pack folder, without the `.png` extension.
  final List<String> stickers;

  String nameIn(bool arabic) => arabic ? nameAr : nameEn;
}

/// Every pack the app ships.
///
/// Adding one is a folder of PNGs plus one entry here: the tray, the sender and
/// the bubble all read this list, so no other file changes and no stored
/// message needs migrating.
const List<ChatStickerPack> chatStickerPacks = [
  ChatStickerPack(
    id: 'mixsay-friends',
    nameAr: 'أصدقاء ميكس',
    nameEn: 'MixSay friends',
    stickers: [
      'sun',
      'cat',
      'heart',
      'thumbs-up',
      'taco',
      'moon',
      'laughing',
      'tea',
      'rainbow',
    ],
  ),
];

/// The id a message carries for one sticker of [pack].
String chatStickerId(ChatStickerPack pack, String sticker) =>
    '${pack.id}/$sticker';

/// The asset a received id paints, or null when this build has no such pack.
///
/// The id arrives from another device, so it is matched against the list above
/// instead of being turned into a path: a made-up string must never reach the
/// asset loader, and an older app that lacks a newer pack shows a placeholder
/// rather than crashing.
String? chatStickerAssetOf(String? stickerId) {
  if (stickerId == null) return null;
  final slash = stickerId.indexOf('/');
  if (slash <= 0 || slash == stickerId.length - 1) return null;
  final packId = stickerId.substring(0, slash);
  final name = stickerId.substring(slash + 1);
  for (final pack in chatStickerPacks) {
    if (pack.id == packId && pack.stickers.contains(name)) {
      return 'assets/stickers/${pack.id}/$name.png';
    }
  }
  return null;
}

/// The sticker tray: one row of packs above the pictures of the chosen pack.
class ChatStickerPicker extends StatefulWidget {
  const ChatStickerPicker({super.key, required this.onSelected});

  /// Receives the sticker id the sender tapped.
  final ValueChanged<String> onSelected;

  @override
  State<ChatStickerPicker> createState() => _ChatStickerPickerState();
}

class _ChatStickerPickerState extends State<ChatStickerPicker> {
  int _pack = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    if (chatStickerPacks.isEmpty) return const SizedBox.shrink();
    final selected =
        chatStickerPacks[_pack.clamp(0, chatStickerPacks.length - 1)];
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: chatStickerPacks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final pack = chatStickerPacks[index];
              final isSelected = index == _pack;
              return ChoiceChip(
                label: Text(pack.nameIn(strings.isArabic)),
                selected: isSelected,
                onSelected: (_) => setState(() => _pack = index),
              );
            },
          ),
        ),
        SizedBox(
          height: 168,
          child: GridView.count(
            crossAxisCount: 5,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              for (final sticker in selected.stickers)
                _StickerButton(
                  asset: 'assets/stickers/${selected.id}/$sticker.png',
                  label: '${selected.nameIn(strings.isArabic)}/$sticker',
                  onTap: () =>
                      widget.onSelected(chatStickerId(selected, sticker)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StickerButton extends StatelessWidget {
  const _StickerButton({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            semanticLabel: label,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.image_not_supported_outlined),
          ),
        ),
      ),
    );
  }
}
