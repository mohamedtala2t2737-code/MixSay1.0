import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/l10n/app_strings.dart';

/// The kind of thing a chat message carries.
///
/// The values are also what is written to Firestore and what `firestore.rules`
/// accepts, so a new type means updating both — a message the server does not
/// recognise is rejected on write, not on read.
enum ChatMessageType {
  text('text'),
  image('image'),
  video('video'),
  file('file'),
  voice('voice'),
  sticker('sticker'),
  gif('gif');

  const ChatMessageType(this.wireValue);

  final String wireValue;

  /// Unknown, missing or future values read back as plain text, so an old build
  /// never shows a blank bubble for a message the sender could write.
  static ChatMessageType fromWire(Object? value) {
    final text = value is String ? value : 'text';
    return ChatMessageType.values.firstWhere(
      (type) => type.wireValue == text,
      orElse: () => ChatMessageType.text,
    );
  }

  /// Everything except a plain message or a bundled sticker is a Storage object
  /// and therefore needs [mediaUrl].
  bool get needsMedia => switch (this) {
    ChatMessageType.text || ChatMessageType.sticker => false,
    _ => true,
  };

  /// Whether the type carries something on its own, so an empty [content] is
  /// not an empty message.
  bool get hasVisiblePayload => this != ChatMessageType.text;

  /// A message that cannot be sent on the free plan, so the control that
  /// creates it is hidden. A bundled sticker only needs the bundledStickers
  /// flag; the type stays available while any sticker source is on, since both
  /// kinds write the same document.
  bool get isGated => switch (this) {
    ChatMessageType.image => !ChatFeatures.images,
    ChatMessageType.video => !ChatFeatures.videos,
    ChatMessageType.file => !ChatFeatures.documents,
    ChatMessageType.voice => !ChatFeatures.voiceMessages,
    ChatMessageType.gif => !ChatFeatures.gifSearch,
    ChatMessageType.sticker => !ChatFeatures.anyStickerSource,
    ChatMessageType.text => false,
  };

  /// The preview shown in the chats list when a message carries no text. It is
  /// built from the locale at paint time, so no English word is ever stored in
  /// Firestore for a photo or a voice note.
  String previewLabel(AppStrings strings) => switch (this) {
    ChatMessageType.image => strings.chatPreviewPhoto,
    ChatMessageType.video => strings.chatPreviewVideo,
    ChatMessageType.file => strings.chatPreviewFile,
    ChatMessageType.voice => strings.chatPreviewVoice,
    ChatMessageType.sticker => strings.chatPreviewSticker,
    ChatMessageType.gif => strings.chatPreviewGif,
    ChatMessageType.text => strings.chatPreviewMessage,
  };
}
