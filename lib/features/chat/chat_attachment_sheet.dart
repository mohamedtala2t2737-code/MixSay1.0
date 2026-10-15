import 'package:flutter/material.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/config/chat_secrets.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';

/// Something the user can add to a message besides text.
enum ChatAttachmentChoice { photo, video, document, gif, sticker }

/// The attach sheet: one row per kind of attachment the plan allows.
///
/// Every one of these costs Storage or a search API, so each row disappears on
/// its own flag in [ChatFeatures]. With the free plan in force
/// [availableOptions] comes back empty and the paperclip that opens this sheet
/// is never drawn — the user never meets a button that cannot work.
///
/// The rows are built from the [options] the caller passes rather than reading
/// the flags here, so a test can show the sheet with any combination.
class ChatAttachmentSheet extends StatelessWidget {
  const ChatAttachmentSheet({
    super.key,
    required this.options,
    required this.onSelected,
  });

  final List<ChatAttachmentChoice> options;
  final ValueChanged<ChatAttachmentChoice> onSelected;

  /// The kinds the current flags and keys allow. A GIF tab without a Tenor key
  /// would only be able to say "not configured", so it does not appear.
  static List<ChatAttachmentChoice> availableOptions() => [
    if (ChatFeatures.images) ChatAttachmentChoice.photo,
    if (ChatFeatures.videos) ChatAttachmentChoice.video,
    if (ChatFeatures.documents) ChatAttachmentChoice.document,
    if (ChatFeatures.gifSearch && ChatSecrets.hasTenorKey)
      ChatAttachmentChoice.gif,
    if (ChatFeatures.userUploadedStickers) ChatAttachmentChoice.sticker,
  ];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            AppListTile(
              leading: Icon(chatAttachmentIcon(option)),
              title: chatAttachmentLabel(strings, option),
              onTap: () => onSelected(option),
            ),
        ],
      ),
    );
  }
}

IconData chatAttachmentIcon(ChatAttachmentChoice choice) =>
    switch (choice) {
      ChatAttachmentChoice.photo => Icons.image_outlined,
      ChatAttachmentChoice.video => Icons.videocam_outlined,
      ChatAttachmentChoice.document => Icons.folder_outlined,
      ChatAttachmentChoice.gif => Icons.gif_box_outlined,
      ChatAttachmentChoice.sticker => Icons.add_to_photos_outlined,
    };

String chatAttachmentLabel(AppStrings strings, ChatAttachmentChoice choice) =>
    switch (choice) {
      ChatAttachmentChoice.photo => strings.sendImage,
      ChatAttachmentChoice.video => strings.attachVideo,
      ChatAttachmentChoice.document => strings.attachDocument,
      ChatAttachmentChoice.gif => strings.attachGif,
      ChatAttachmentChoice.sticker => strings.attachStickerFromGallery,
    };

/// Opens the sheet and reports what was chosen, or null when it was dismissed.
Future<ChatAttachmentChoice?> showChatAttachmentSheet(
  BuildContext context, {
  List<ChatAttachmentChoice>? options,
}) async {
  final choices = options ?? ChatAttachmentSheet.availableOptions();
  if (choices.isEmpty) return null;
  return showModalBottomSheet<ChatAttachmentChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ChatAttachmentSheet(
      options: choices,
      onSelected: (choice) => Navigator.of(sheetContext).pop(choice),
    ),
  );
}
