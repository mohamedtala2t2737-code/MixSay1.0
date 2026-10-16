/// Every paid or plan-limited chat capability behind one switch.
///
/// Flipping a value here is the ONLY code change needed to turn the feature on
/// once the matching Firebase work is deployed (see `ENABLE_FEATURES.md`). A
/// false flag hides the control completely — the attach sheet, the mic, the GIF
/// tab — so the user never meets a button that cannot work.
///
/// The defaults match the free Spark plan of project `ms-chat-b9635`: text,
/// emoji and bundled stickers cost nothing, anything that writes to Cloud
/// Storage, records audio, or calls a paid search API is off.
class ChatFeatures {
  const ChatFeatures._();

  /// Unicode emoji keyboard. Ships with the app and needs no backend.
  static const bool emojiPicker = true;

  /// Sticker packs bundled in `assets/stickers/`, sent as a pack id.
  static const bool bundledStickers = true;

  /// Photos from the gallery or camera: uploads to Cloud Storage.
  static const bool images = false;

  /// Video messages: Storage plus a generated thumbnail.
  static const bool videos = false;

  /// Document attachments: Storage plus a system file picker.
  static const bool documents = false;

  /// Voice notes: microphone recording and Storage upload.
  static const bool voiceMessages = false;

  /// Stickers the user uploads themselves. Flipping this is not enough: a
  /// `sticker` message carries an id and no `mediaUrl`, which is what
  /// `firestore.rules` accepts, so the upload needs a rule and a schema first.
  static const bool userUploadedStickers = false;

  /// Tenor search. Needs an API key, so it also stays off until the key is
  /// present in the git-ignored `chat.secrets.json`.
  static const bool gifSearch = false;

  /// Push while the app is closed. Needs Cloud Functions, which need the Blaze
  /// plan; in-app notifications keep working regardless.
  static const bool pushNotifications = false;

  /// Voice and video calls. Needs the `flutter_webrtc` dependency, a `calls`
  /// collection with rules of its own, and TURN credentials for the networks
  /// where public STUN alone cannot punch through, so the app ships without it.
  /// While this is false the two call icons are not drawn in the chat app bar
  /// at all.
  static const bool calls = false;

  /// Upload ceilings enforced both client-side and in `storage.rules`. Keep the
  /// two in step or the server starts rejecting what the app accepted.
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int maxVideoBytes = 25 * 1024 * 1024;
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const int maxVoiceBytes = 5 * 1024 * 1024;

  /// Longest text message the rules allow.
  static const int maxTextLength = 4000;

  /// Any media feature at all. The attach button disappears entirely when none
  /// of them is on, which is the state the free plan ships in.
  static const bool anyMediaAttachment =
      images || videos || documents || voiceMessages || gifSearch;

  static const bool anyStickerSource = bundledStickers || userUploadedStickers;
}
