import 'dart:io';
import 'dart:typed_data';

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
    this.thumbnailPath,
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

  /// A still frame generated next to a clip, so reading a thread never
  /// downloads the video just to show what it looks like. Null for every other
  /// kind of attachment.
  final String? thumbnailPath;

  static const _typeKey = 'media_type';
  static const _pathKey = 'local_path';
  static const _nameKey = 'file_name';
  static const _sizeKey = 'byte_size';
  static const _captionKey = 'caption';
  static const _durationKey = 'duration_ms';
  static const _thumbnailKey = 'thumb_local_path';

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

  /// The poster travels beside the clip, in the same folder, named after the
  /// same message. `storage.rules` accepts it because the folder is the
  /// sender's own; `firestore.rules` accepts it as a `thumbUrl` for the same
  /// reason.
  String thumbnailStoragePath({
    required String conversationId,
    required String senderId,
    required String clientId,
  }) =>
      'chats/$conversationId/$senderId/'
      '$clientId$chatMediaThumbnailSuffix.jpg';

  ChatAttachmentDraft copyWith({
    String? localPath,
    int? byteSize,
    String? caption,
    String? thumbnailPath,
  }) => ChatAttachmentDraft(
    type: type,
    localPath: localPath ?? this.localPath,
    fileName: fileName,
    byteSize: byteSize ?? this.byteSize,
    caption: caption ?? this.caption,
    durationMs: durationMs,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
  );

  /// The size the ceiling check reads, measured from the file instead of from
  /// the queue. An entry written by an older build has no recorded size, and
  /// guessing one would either refuse a valid photo or accept a huge video.
  Future<ChatAttachmentDraft> withMeasuredSize() async {
    if (!needsUpload || byteSize > 0) return this;
    return copyWith(byteSize: await File(localPath).length());
  }

  /// Every file on this device a queue entry owns: the staged upload and, for a
  /// clip, the poster staged beside it. An entry that owns none is a plain
  /// message or a queued GIF, which is only a url — deleting either path would
  /// throw the app at a file that never existed.
  static List<String> queuedFilePaths(Map<String, dynamic> entry) {
    final draft = fromQueueFields(entry);
    if (draft == null || !draft.needsUpload) return const [];
    final poster = draft.thumbnailPath;
    return poster == null ? [draft.localPath] : [draft.localPath, poster];
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
    final thumbnail = entry[_thumbnailKey];
    return (type == null || type is String) &&
        (sticker == null || sticker is String) &&
        (path == null || (path is String && path.isNotEmpty)) &&
        (thumbnail == null || (thumbnail is String && thumbnail.isNotEmpty)) &&
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
    if (thumbnailPath != null) _thumbnailKey: thumbnailPath,
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
    final thumbnail = entry[_thumbnailKey];
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
      thumbnailPath: thumbnail is String ? thumbnail : null,
    );
  }
}

/// A clip's poster travels beside the video under the same client id, in the
/// sender's own folder. One name for it keeps the upload path, the staged copy
/// and the queue entry agreeing.
const String chatMediaThumbnailSuffix = '_thumb';

/// The content type a generated poster is uploaded with, which is also the one
/// `storage.rules` reads to pick the image ceiling.
const String chatMediaThumbnailContentType = 'image/jpeg';

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

/// The longest name a file tile shows. Longer names are cut with the extension
/// kept, because the extension is what tells the receiver what they are opening.
const int chatReceivedNameDisplayLength = 60;

/// The label for a document that arrived with no usable name. The sender writes
/// [fileName] themselves, so it can be empty, all dots, or a path from their
/// device.
const String chatReceivedNameFallback = 'attachment';

/// The name a receiver may safely show and save a sent document under.
///
/// [chatSafeReceivedName] keeps only the last path segment, drops the
/// characters a filesystem refuses and falls back when nothing is left, so a
/// name written by the other side can never point at another folder.
String chatSafeReceivedName(String? rawName) {
  final segment = (rawName ?? '').split(RegExp(r'[/\\]')).last;
  final cleaned = segment
      .replaceAll(RegExp('[\u0000-\u001F:*?"<>|]'), '')
      .trim();
  if (cleaned.isEmpty || cleaned.replaceAll('.', '').isEmpty) {
    return chatReceivedNameFallback;
  }
  if (cleaned.length <= chatReceivedNameDisplayLength) return cleaned;
  final extension = chatMediaExtension(cleaned);
  final head = cleaned.substring(0, chatReceivedNameDisplayLength);
  return extension.isEmpty ? '$head…' : '$head….$extension';
}

/// The draft for a clip the gallery handed over.
///
/// Nothing is re-encoded or copied: a phone can spend minutes on a video, and
/// [chatMediaRejection] refuses an oversized one before a byte leaves the
/// device. The stored object keeps the clip's own extension because
/// `storage.rules` reads it to pick the ceiling.
Future<ChatAttachmentDraft> chatVideoDraft({
  required String pickedPath,
  required String pickedName,
  required String clientId,
}) async {
  final extension = chatMediaExtension(pickedName);
  return ChatAttachmentDraft(
    type: ChatMessageType.video,
    localPath: pickedPath,
    fileName: '$clientId.${extension.isEmpty ? 'mp4' : extension}',
    byteSize: await File(pickedPath).length(),
  );
}

/// A picked document, staged in [directory] under the message's own client id.
///
/// The copy is not ceremony: a system picker can hand back a uri only this app
/// can read, and the offline queue has to find the same bytes after a restart.
/// [fileName] stays what the sender named it, because that is the label the
/// receiver reads — [chatSafeReceivedName] makes it safe on their side.
Future<ChatAttachmentDraft> chatDocumentDraft({
  required String fileName,
  required String? pickedPath,
  required Uint8List? pickedBytes,
  required String directory,
  required String clientId,
}) async {
  final extension = chatMediaExtension(fileName);
  final target =
      '$directory/$clientId${extension.isEmpty ? '' : '.$extension'}';
  final source = pickedPath;
  if (source != null) {
    await File(source).copy(target);
  } else if (pickedBytes case final bytes?) {
    await File(target).writeAsBytes(bytes);
  } else {
    throw const ChatAttachmentRejectedException('empty');
  }
  return ChatAttachmentDraft(
    type: ChatMessageType.file,
    localPath: target,
    fileName: fileName,
    byteSize: await File(target).length(),
  );
}

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
