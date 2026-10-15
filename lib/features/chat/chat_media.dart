import 'dart:io';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';

/// An attachment the user picked, described the same way whether it is going
/// out now or sitting in the offline queue.
///
/// The queue stores these fields as plain JSON, so everything here is a string,
/// an int or a path — never a platform object a restart could not rebuild.
class ChatAttachmentDraft {
  const ChatAttachmentDraft({
    required this.type,
    required this.localPath,
    required this.fileName,
    required this.byteSize,
    this.caption,
    this.durationMs,
  });

  final ChatMessageType type;

  /// The file on this device. A GIF from the search tab has no local file and
  /// is sent by its url instead, so this is the queue's copy or a remote url.
  final String localPath;

  /// The name the receiver sees for a document; a photo keeps its own.
  final String fileName;

  /// The size that was actually measured before the upload started, which the
  /// ceiling check reads and the file tile shows.
  final int byteSize;

  final String? caption;
  final int? durationMs;

  static const _typeKey = 'media_type';
  static const _pathKey = 'local_path';
  static const _nameKey = 'file_name';
  static const _sizeKey = 'byte_size';
  static const _captionKey = 'caption';
  static const _durationKey = 'duration_ms';

  /// The wire key the queue has always used for a photo. A queued message from
  /// an older build still carries it, so reading must accept both.
  static const _legacyPathKey = 'local_image_path';

  /// What the upload path is called: the sender's own id and the client id of
  /// the message, which `storage.rules` allows only for that pair.
  String storageObjectName(String clientId) =>
      '$clientId.${chatMediaExtension(fileName)}';

  String get contentType => chatMediaType(type, fileName);

  /// Whether the bytes have to reach Cloud Storage before the message can be
  /// written. A GIF from the search tab already carries a public url, which is
  /// what `firestore.rules` asks for that type, so nothing is uploaded for it.
  bool get needsUpload => switch (type) {
    ChatMessageType.image ||
    ChatMessageType.video ||
    ChatMessageType.file ||
    ChatMessageType.voice ||
    ChatMessageType.sticker => true,
    ChatMessageType.gif || ChatMessageType.text => false,
  };

  /// The Storage object this attachment gets: the sender's own folder inside
  /// the conversation, named after the message's client id. `storage.rules`
  /// only accepts a write when the folder really is the sender's.
  String storagePath({
    required String conversationId,
    required String senderId,
    required String clientId,
  }) => 'chats/$conversationId/$senderId/${storageObjectName(clientId)}';

  ChatAttachmentDraft copyWith({
    String? localPath,
    int? byteSize,
    String? caption,
  }) => ChatAttachmentDraft(
    type: type,
    localPath: localPath ?? this.localPath,
    fileName: fileName,
    byteSize: byteSize ?? this.byteSize,
    caption: caption ?? this.caption,
    durationMs: durationMs,
  );

  /// The size the ceiling check reads, measured from the file instead of from
  /// the queue. An entry written by an older build has no recorded size, and
  /// guessing one would either refuse a valid photo or accept a huge video.
  Future<ChatAttachmentDraft> withMeasuredSize() async {
    if (!needsUpload || byteSize > 0) return this;
    return copyWith(byteSize: await File(localPath).length());
  }

  /// The staged file a queue entry owns, or null when it owns none: a plain
  /// message has no attachment and a queued GIF is only a url, so deleting
  /// either path would throw the app at a file that never existed.
  static String? queuedFilePath(Map<String, dynamic> entry) {
    final draft = fromQueueFields(entry);
    return draft != null && draft.needsUpload ? draft.localPath : null;
  }

  /// Whether an entry's attachment description is usable. The queue holds JSON
  /// a previous build wrote, so a wrong type here means the entry is dropped
  /// rather than sent as a half-built message.
  static bool queueFieldsAreValid(Map<String, dynamic> entry) {
    final type = entry[_typeKey];
    final path = entry[_pathKey] ?? entry[_legacyPathKey];
    final name = entry[_nameKey];
    final size = entry[_sizeKey];
    final caption = entry[_captionKey];
    final duration = entry[_durationKey];
    final sticker = entry['sticker_id'];
    return (type == null || type is String) &&
        (sticker == null || sticker is String) &&
        (path == null || (path is String && path.isNotEmpty)) &&
        (name == null || name is String) &&
        (size == null || (size is int && size >= 0)) &&
        (caption == null || caption is String) &&
        (duration == null || (duration is int && duration >= 0));
  }

  /// The queue JSON. A text-only message writes none of these keys.
  Map<String, dynamic> toQueueFields() => {
    _typeKey: type.wireValue,
    _pathKey: localPath,
    _nameKey: fileName,
    _sizeKey: byteSize,
    if (caption != null && caption!.isNotEmpty) _captionKey: caption,
    if (durationMs != null) _durationKey: durationMs,
  };

  /// Rebuild a draft from a queue entry, or null when the entry is a plain
  /// message or its media description is unusable.
  static ChatAttachmentDraft? fromQueueFields(Map<String, dynamic> entry) {
    final rawType = entry[_typeKey];
    final path = entry[_pathKey] ?? entry[_legacyPathKey];
    if (path is! String || path.isEmpty) return null;
    final name = entry[_nameKey];
    final size = entry[_sizeKey];
    final duration = entry[_durationKey];
    final caption = entry[_captionKey];
    return ChatAttachmentDraft(
      // An entry queued by an older build carries only the photo key, and a
      // photo was the only attachment that app could queue.
      type: rawType is String
          ? ChatMessageType.fromWire(rawType)
          : ChatMessageType.image,
      localPath: path,
      fileName: name is String && name.isNotEmpty ? name : path.split('/').last,
      byteSize: size is int ? size : 0,
      caption: caption is String ? caption : null,
      durationMs: duration is int ? duration : null,
    );
  }
}

/// The lower-case extension, without the dot, that a stored object gets.
///
/// Photos, videos and voice notes are re-encoded to one format each, so the
/// receiver can always play what arrived. A document keeps its own extension
/// because the name is what the receiver opens it with.
String chatMediaExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// The content type the upload declares, which is what `storage.rules` uses to
/// pick the size ceiling. Unknown document types fall back to the generic one
/// rather than claiming to be something the receiver would open blindly.
String chatMediaType(ChatMessageType type, String fileName) {
  final extension = chatMediaExtension(fileName);
  return switch (type) {
    ChatMessageType.image => _imageTypes[extension] ?? 'image/jpeg',
    ChatMessageType.video => _videoTypes[extension] ?? 'video/mp4',
    ChatMessageType.voice => _audioTypes[extension] ?? 'audio/m4a',
    ChatMessageType.gif => 'image/gif',
    ChatMessageType.file =>
      _documentTypes[extension] ?? 'application/octet-stream',
    ChatMessageType.sticker => 'image/png',
    ChatMessageType.text => 'text/plain',
  };
}

const _imageTypes = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

const _videoTypes = <String, String>{
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
};

const _audioTypes = <String, String>{
  'm4a': 'audio/m4a',
  'aac': 'audio/aac',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
  'amr': 'audio/amr',
};

const _documentTypes = <String, String>{
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'json': 'application/json',
  'csv': 'text/csv',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

/// The byte ceiling for one kind of attachment, or null when the kind needs no
/// upload at all. These are the same ceilings `storage.rules` enforces, so the
/// app refuses an oversized file instead of uploading it for nothing.
int? chatMediaLimitFor(ChatMessageType type) => switch (type) {
  ChatMessageType.image => ChatFeatures.maxImageBytes,
  ChatMessageType.video => ChatFeatures.maxVideoBytes,
  ChatMessageType.file => ChatFeatures.maxFileBytes,
  ChatMessageType.voice => ChatFeatures.maxVoiceBytes,
  ChatMessageType.sticker ||
  ChatMessageType.gif ||
  ChatMessageType.text => null,
};

/// The longest voice note the app records. `firestore.rules` refuses a
/// `durationMs` above ten minutes, so a longer recording would fail on the
/// write rather than on the microphone.
const int chatMediaMaxDurationMs = 600000;

/// Why an attachment cannot be sent, or null when it may.
String? chatMediaRejectionReason(ChatAttachmentDraft draft) {
  final limit = chatMediaLimitFor(draft.type);
  if (limit == null) return null;
  if (draft.byteSize <= 0) return 'empty';
  if (draft.byteSize > limit) return 'tooLarge';
  return null;
}

/// The refusal to raise for a draft that cannot go out, already carrying the
/// ceiling it hit so the screen can name it instead of saying "failed".
ChatAttachmentRejectedException? chatMediaRejection(ChatAttachmentDraft draft) {
  final reason = chatMediaRejectionReason(draft);
  if (reason == null) return null;
  return ChatAttachmentRejectedException(
    reason,
    limitBytes: chatMediaLimitFor(draft.type),
  );
}

/// Thrown when an attachment reaches the repository anyway — a queue entry
/// whose file grew, or a caller that skipped the check. The reason is one of
/// the values [chatMediaRejectionReason] returns, so the screen can say which
/// limit was hit without re-reading the file.
class ChatAttachmentRejectedException implements Exception {
  const ChatAttachmentRejectedException(this.reason, {this.limitBytes});

  final String reason;
  final int? limitBytes;

  @override
  String toString() => 'ChatAttachmentRejectedException: $reason';
}
