import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/features/chat/chat_media.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/pending_queue_service.dart';

class ActiveChatState {
  static final _openConversations = <String>[];

  static String? get conversationId =>
      _openConversations.isEmpty ? null : _openConversations.last;

  static void open(String conversationId) {
    _openConversations.add(conversationId);
  }

  static void close(String conversationId) {
    final index = _openConversations.lastIndexOf(conversationId);
    if (index >= 0) _openConversations.removeAt(index);
  }
}

/// Lets the sender walk away from an upload that is already running.
///
/// [cancel] before the transfer starts still cancels it: the task is handed to
/// [attach] the moment Storage accepts it, and a request that arrived earlier
/// is applied there. Without that, a cancel pressed while the file was still
/// opening would do nothing and the bytes would travel anyway.
class ChatUploadController {
  UploadTask? _task;
  bool _cancelRequested = false;

  bool get isCancelled => _cancelRequested;

  void cancel() {
    _cancelRequested = true;
    _task?.cancel();
  }

  void attach(UploadTask task) {
    _task = task;
    if (_cancelRequested) task.cancel();
  }

  void detach() => _task = null;
}

class ChatConversationPreview {
  const ChatConversationPreview({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherFullName,
    this.otherAvatarUrl,
    this.lastMessageContent,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.lastMessageType = ChatMessageType.text,
    this.lastSenderId,
  });

  final String id;
  final String otherUserId;
  final String otherUsername;
  final String otherFullName;
  final String? otherAvatarUrl;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// What the last message was, so a photo shows as "Photo" instead of the
  /// empty text field it carries.
  final ChatMessageType lastMessageType;
  final String? lastSenderId;

  ChatConversationPreview withPublicProfile(Map<String, dynamic>? profile) =>
      ChatConversationPreview(
        id: id,
        otherUserId: otherUserId,
        otherUsername: profile?['username'] as String? ?? otherUsername,
        otherFullName: profile?['fullName'] as String? ?? otherFullName,
        otherAvatarUrl: profile == null
            ? otherAvatarUrl
            : profile['avatarUrl'] as String?,
        lastMessageContent: lastMessageContent,
        lastMessageAt: lastMessageAt,
        unreadCount: unreadCount,
        lastMessageType: lastMessageType,
        lastSenderId: lastSenderId,
      );

  factory ChatConversationPreview.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String userId,
  ) => ChatConversationPreview.fromData(
    id: document.id,
    data: document.data(),
    userId: userId,
  );

  factory ChatConversationPreview.fromData({
    required String id,
    required Map<String, dynamic> data,
    required String userId,
  }) {
    final members = (data['members'] as List<dynamic>? ?? []).cast<String>();
    final otherUserId = members.firstWhere(
      (member) => member != userId,
      orElse: () => '',
    );
    final participants = (data['participants'] as Map<String, dynamic>? ?? {});
    final otherUser =
        (participants[otherUserId] as Map<String, dynamic>? ?? {});
    final unreadCounts = (data['unreadCounts'] as Map<String, dynamic>? ?? {});

    return ChatConversationPreview(
      id: id,
      otherUserId: otherUserId,
      otherUsername: otherUser['username'] as String? ?? '',
      otherFullName: otherUser['fullName'] as String? ?? '',
      otherAvatarUrl: otherUser['avatarUrl'] as String?,
      lastMessageContent: data['lastMessageContent'] as String?,
      lastMessageAt: _dateTime(data['lastMessageAt']),
      unreadCount: _asInt(unreadCounts[userId]),
      lastMessageType: ChatMessageType.fromWire(data['lastMessageType']),
      lastSenderId: data['lastSenderId'] as String?,
    );
  }
}

class ChatConversationInfo {
  const ChatConversationInfo({
    required this.conversationId,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherFullName,
    this.otherAvatarUrl,
    this.otherProfileMissing = false,
  });

  final String conversationId;
  final String otherUserId;
  final String otherUsername;
  final String otherFullName;
  final String? otherAvatarUrl;

  /// The other account's public profile document is gone, which is what a
  /// deleted account looks like. The name on the conversation document is then
  /// the last known one, and the screen says so instead of pretending the
  /// account still exists.
  final bool otherProfileMissing;
}

class ChatUserPreview {
  const ChatUserPreview({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.mediaPath,
    this.clientId,
    this.localImagePath,
    this.documentSnapshot,
    required this.createdAt,
    required this.status,
    this.type = ChatMessageType.text,
    this.thumbUrl,
    this.fileName,
    this.fileSize,
    this.durationMs,
    this.stickerId,
    this.replyTo,
    this.deletedFor = const [],
    this.deletedForEveryone = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaPath;
  final String? clientId;

  /// The file on this device for a message still sitting in the offline queue,
  /// whatever it carries: a photo, a video, a voice note or a document. Once
  /// the upload succeeds the bubble reads [mediaPath] instead.
  final String? localImagePath;
  final QueryDocumentSnapshot<Map<String, dynamic>>? documentSnapshot;
  final DateTime createdAt;
  final String status;
  final ChatMessageType type;
  final String? thumbUrl;
  final String? fileName;
  final int? fileSize;
  final int? durationMs;
  final String? stickerId;
  final ChatReply? replyTo;

  /// The members who hid this message on their own side. Never the sender's
  /// secret: `firestore.rules` only lets a member add themself.
  final List<String> deletedFor;

  /// The sender chose "delete for everyone", so both sides show a tombstone.
  final bool deletedForEveryone;

  /// Whether [userId] should see this message at all.
  bool hiddenFor(String userId) =>
      deletedForEveryone || deletedFor.contains(userId);

  factory ChatMessage.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String conversationId,
  ) {
    final data = document.data();
    return ChatMessage.fromData(
      id: document.id,
      conversationId: conversationId,
      data: data,
      documentSnapshot: document,
    );
  }

  factory ChatMessage.fromData({
    required String id,
    required String conversationId,
    required Map<String, dynamic> data,
    QueryDocumentSnapshot<Map<String, dynamic>>? documentSnapshot,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: data['senderId'] as String? ?? '',
      content: data['content'] as String? ?? '',
      mediaPath: data['mediaPath'] as String? ?? data['mediaUrl'] as String?,
      clientId: data['clientId'] as String?,
      documentSnapshot: documentSnapshot,
      createdAt: _dateTime(data['createdAt']) ?? DateTime.now(),
      status: data['status'] as String? ?? 'sent',
      type: ChatMessageType.fromWire(data['type']),
      thumbUrl: data['thumbUrl'] as String?,
      fileName: data['fileName'] as String?,
      fileSize: data['fileSize'] is int ? data['fileSize'] as int : null,
      durationMs: data['durationMs'] is int ? data['durationMs'] as int : null,
      stickerId: data['stickerId'] as String?,
      replyTo: ChatReply.fromData(data['replyTo'] as Map<String, dynamic>?),
      deletedFor: (data['deletedFor'] as List<dynamic>? ?? []).cast<String>(),
      deletedForEveryone: data['deletedForEveryone'] == true,
    );
  }

  factory ChatMessage.fromPending(Map<String, dynamic> entry) {
    final attachment = ChatAttachmentDraft.fromQueueFields(entry);
    final stickerId = entry['sticker_id'] is String
        ? entry['sticker_id'] as String
        : null;
    // A queued upload still has to reach Storage, so the bubble shows the file
    // on this device. A GIF carries the public url it will be written with.
    final localPath = attachment != null && attachment.needsUpload
        ? attachment.localPath
        : null;
    return ChatMessage(
      id: 'pending-${entry['client_id']}',
      conversationId: entry['conversation_id'] as String,
      senderId: entry['sender_id'] as String,
      content: entry['content'] as String? ?? '',
      mediaPath: localPath ?? attachment?.localPath,
      clientId: entry['client_id'] as String,
      localImagePath: localPath,
      createdAt: DateTime.parse(entry['created_at'] as String),
      status: entry['state'] as String? ?? 'sending',
      type: stickerId != null
          ? ChatMessageType.sticker
          : (attachment?.type ?? ChatMessageType.text),
      stickerId: stickerId,
      // Only a document is named to the receiver; a photo keeps its random
      // staging name, which would show up as a meaningless label.
      fileName: attachment?.type == ChatMessageType.file
          ? attachment?.fileName
          : null,
      fileSize: attachment == null || attachment.byteSize <= 0
          ? null
          : attachment.byteSize,
      durationMs: attachment?.durationMs,
      replyTo: ChatReply.fromData(entry['reply_to'] as Map<String, dynamic>?),
    );
  }

  /// Firestore documents written before this version of the rules only carry
  /// the legacy fields, so a media message with no `type` still needs the right
  /// label in the chats list.
  ChatMessageType inferredType() =>
      type == ChatMessageType.text && mediaPath != null
      ? ChatMessageType.image
      : type;
}

/// The quoted snapshot of the message a reply points at.
///
/// Only a short copy travels with the new message instead of a document
/// reference, so rendering a reply costs no extra read and a message deleted
/// for everyone still shows what was quoted. The rules cap [content] at the
/// same 300 characters [ChatReply.quoteFrom] produces.
class ChatReply {
  const ChatReply({
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.type,
  });

  static const maxContentLength = 300;

  final String messageId;
  final String senderId;
  final String content;
  final ChatMessageType type;

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderId': senderId,
    'content': content,
    'type': type.wireValue,
  };

  /// Null for a message that quotes nothing, and for a malformed map, which an
  /// older document can hold if it was written before the rules validated
  /// `replyTo`.
  static ChatReply? fromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final messageId = data['messageId'] as String? ?? '';
    if (messageId.isEmpty) return null;
    return ChatReply(
      messageId: messageId,
      senderId: data['senderId'] as String? ?? '',
      content: data['content'] as String? ?? '',
      type: ChatMessageType.fromWire(data['type']),
    );
  }

  /// Truncates on whole code points so an emoji in the quoted text cannot be
  /// cut in half.
  static ChatReply quoteFrom(ChatMessage message) {
    final runes = message.content.runes.toList();
    return ChatReply(
      messageId: message.id,
      senderId: message.senderId,
      content: String.fromCharCodes(
        runes.length > maxContentLength
            ? runes.sublist(0, maxContentLength)
            : runes,
      ),
      type: message.inferredType(),
    );
  }
}

DateTime? _dateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int _asInt(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

class _CachedPublicProfile {
  const _CachedPublicProfile({required this.expiresAt, required this.value});

  final DateTime expiresAt;
  final Future<Map<String, dynamic>?> value;
}

class ChatRepository {
  ChatRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    PendingQueueService? pendingQueue,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _pendingQueue = pendingQueue ?? PendingQueueService.instance;

  static const _messagePageSize = 30;

  /// Rows one page of the conversation list downloads. It is public because a
  /// short page is how the list knows it has reached the end.
  static const conversationPageSize = 50;
  static const _statusPageSize = 50;
  static const _profileCacheTtl = Duration(minutes: 10);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final PendingQueueService _pendingQueue;
  final _profileCache = <String, _CachedPublicProfile>{};

  String get _me {
    final id = _auth.currentUser?.uid;
    if (id == null) throw StateError('Sign in with Firebase to use chat');
    return id;
  }

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  String createClientId() => _newUuid();

  Future<List<ChatUserPreview>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final users = await _firestore
        .collection('publicProfiles')
        .orderBy('usernameLowercase')
        .startAt([normalized])
        .endAt(['$normalized\uf8ff'])
        .limit(20)
        .get();
    return users.docs.where((document) => document.id != _me).map((document) {
      final data = document.data();
      return ChatUserPreview(
        id: document.id,
        username: data['username'] as String? ?? '',
        fullName:
            data['fullName'] as String? ?? data['full_name'] as String? ?? '',
        avatarUrl:
            data['avatarUrl'] as String? ?? data['avatar_url'] as String?,
      );
    }).toList();
  }

  static String buildConversationId(List<String> memberIds) {
    if (memberIds.length != 2 ||
        memberIds[0].isEmpty ||
        memberIds[1].isEmpty ||
        memberIds[0] == memberIds[1]) {
      throw ArgumentError.value(memberIds, 'memberIds');
    }
    final members = [...memberIds]..sort();
    return '${members[0].length}_${members[0]}${members[1]}';
  }

  /// The member that is not [senderId], or null for a malformed document. Both
  /// this and the rules treat a thread as exactly two people.
  static String? recipientOf(Iterable<String> members, String senderId) {
    final recipient = members.where((member) => member != senderId).toList();
    return recipient.length == 1 ? recipient.single : null;
  }

  /// Read receipts only move forward, mirroring the `messages/{messageId}`
  /// update rule. Keeping the ladder in one place is what stops a retried
  /// status write from downgrading a message the other side already read.
  static bool canMoveStatus({required String from, required String to}) =>
      (from == 'sent' && (to == 'delivered' || to == 'read')) ||
      (from == 'delivered' && to == 'read');

  /// Merges freshly received messages into what the thread already shows.
  /// A queued send has id `pending-<clientId>` while the same message after it
  /// reaches Firestore is keyed by [clientId], so the client id is what pairs
  /// them; without that the sender would see their own message twice.
  static List<ChatMessage> mergeMessages(
    List<ChatMessage> loaded,
    Iterable<ChatMessage> incoming,
  ) {
    final merged = [...loaded];
    for (final message in incoming) {
      final index = merged.indexWhere(
        (item) =>
            item.id == message.id ||
            (message.clientId != null && item.clientId == message.clientId),
      );
      if (index == -1) {
        merged.add(message);
      } else {
        merged[index] = message;
      }
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  /// Whether a queue entry may be attempted now: it has to be mine, not
  /// permanently failed, and not still inside its backoff window.
  static bool isReadyToSend(
    Map<String, dynamic> entry, {
    required String senderId,
    DateTime? now,
  }) {
    if (entry['sender_id'] != senderId || entry['state'] == 'failed') {
      return false;
    }
    final nextAttempt = DateTime.tryParse(
      entry['next_attempt_at'] as String? ?? '',
    );
    return nextAttempt == null || !nextAttempt.isAfter(now ?? DateTime.now());
  }

  /// Waits 2^attempts seconds, capped, so a device that stays offline does not
  /// hammer Firestore with every app open.
  static Duration retryBackoff(int attempts) =>
      Duration(seconds: min(300, 1 << attempts));

  static int nextAttemptCount(dynamic current) =>
      (_asInt(current) + 1).clamp(1, 8).toInt();

  Future<String> getOrCreateConversation(String otherUserId) async {
    final currentUserId = _me;
    if (otherUserId.isEmpty || otherUserId == currentUserId) {
      throw ArgumentError.value(otherUserId, 'otherUserId');
    }

    final members = [currentUserId, otherUserId]..sort();
    final conversationId = buildConversationId(members);
    final reference = _conversations.doc(conversationId);

    final participantProfiles = <String, Map<String, dynamic>>{};
    for (final userId in members) {
      final profile = await _firestore
          .collection('publicProfiles')
          .doc(userId)
          .get();
      final data = profile.data();
      if (data == null) {
        throw StateError('Firebase profile not found for participant $userId');
      }
      participantProfiles[userId] = _participantFields(data);
    }

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) return;
      transaction.set(reference, {
        'members': members,
        'participants': participantProfiles,
        'lastMessageContent': null,
        'lastMessageAt': null,
        'unreadCounts': {for (final userId in members) userId: 0},
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return conversationId;
  }

  /// Turn fetched conversation documents into list rows, refreshing each row's
  /// name and avatar from the live profile. A profile that cannot be read only
  /// costs that one row its fresh copy; the conversation still shows.
  Future<List<ChatConversationPreview>> _previewRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    String currentUserId,
  ) => Future.wait(
    documents.map((document) async {
      final preview = ChatConversationPreview.fromFirestore(
        document,
        currentUserId,
      );
      try {
        final profile = await _getPublicProfile(preview.otherUserId);
        return preview.withPublicProfile(profile);
      } catch (error, stackTrace) {
        _logFailure('load a conversation member profile', error, stackTrace);
        return preview;
      }
    }),
  );

  Stream<List<ChatConversationPreview>> watchConversations({String? userId}) {
    final currentUserId = userId ?? _auth.currentUser?.uid;
    if (currentUserId == null) {
      return Stream.error(StateError('Sign in with Firebase to use chat'));
    }
    // The server does the ordering: without it every conversation of the user
    // is downloaded on every change just to be sorted locally, and the list
    // grows without a bound. Documents with no message yet (lastMessageAt null)
    // sort last, which is where the old local sort put them.
    return _conversations
        .where('members', arrayContains: currentUserId)
        .orderBy('lastMessageAt', descending: true)
        .limit(conversationPageSize)
        .snapshots()
        .asyncMap((snapshot) => _previewRows(snapshot.docs, currentUserId));
  }

  /// The page of the conversation list older than [before], which is the
  /// `lastMessageAt` of the oldest row already on screen. Scrolling to the
  /// bottom then costs one paged read instead of downloading every connection
  /// the user has.
  Future<List<ChatConversationPreview>> fetchOlderConversations({
    String? userId,
    required DateTime before,
  }) async {
    final currentUserId = userId ?? _auth.currentUser?.uid;
    if (currentUserId == null) {
      throw StateError('Sign in with Firebase to use chat');
    }
    final snapshot = await _conversations
        .where('members', arrayContains: currentUserId)
        .orderBy('lastMessageAt', descending: true)
        .startAfter([Timestamp.fromDate(before)])
        .limit(conversationPageSize)
        .get();
    return _previewRows(snapshot.docs, currentUserId);
  }

  Future<ChatConversationInfo> getConversationInfo(
    String conversationId,
  ) async {
    final currentUserId = _me;
    final document = await _conversations.doc(conversationId).get();
    final data = document.data();
    if (!document.exists || data == null) {
      throw StateError('Conversation not found');
    }
    final members = (data['members'] as List<dynamic>? ?? []).cast<String>();
    if (!members.contains(currentUserId)) {
      throw StateError('You are not a member of this conversation');
    }
    final otherUserId = members.firstWhere(
      (member) => member != currentUserId,
      orElse: () => '',
    );
    final participants = data['participants'] as Map<String, dynamic>? ?? {};
    final fallback =
        participants[otherUserId] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    Map<String, dynamic>? profile;
    var profileMissing = false;
    try {
      profile = await _getPublicProfile(otherUserId);
      profileMissing = profile == null;
    } catch (error, stackTrace) {
      _logFailure('load a conversation member profile', error, stackTrace);
    }
    final otherUser = profile ?? fallback;
    return ChatConversationInfo(
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherUsername: otherUser['username'] as String? ?? '',
      otherFullName:
          otherUser['fullName'] as String? ??
          otherUser['full_name'] as String? ??
          '',
      otherAvatarUrl:
          otherUser['avatarUrl'] as String? ??
          otherUser['avatar_url'] as String?,
      otherProfileMissing: profileMissing,
    );
  }

  Future<Map<String, dynamic>?> _getPublicProfile(String userId) async {
    final cached = _profileCache[userId];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.value;
    }
    final future = _firestore.collection('publicProfiles').doc(userId).get();
    final entry = _CachedPublicProfile(
      expiresAt: DateTime.now().add(_profileCacheTtl),
      value: future.then((snapshot) => snapshot.data()),
    );
    _profileCache[userId] = entry;
    try {
      return await entry.value;
    } catch (error, stackTrace) {
      _logFailure('cache a public profile', error, stackTrace);
      if (identical(_profileCache[userId], entry)) {
        _profileCache.remove(userId);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _participantFields(Map<String, dynamic> profile) => {
    'username': profile['username'] as String? ?? '',
    'fullName':
        profile['fullName'] as String? ?? profile['full_name'] as String? ?? '',
    'avatarUrl':
        profile['avatarUrl'] as String? ?? profile['avatar_url'] as String?,
  };

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Unable to $operation: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  CollectionReference<Map<String, dynamic>> _messages(String conversationId) =>
      _conversations.doc(conversationId).collection('messages');

  Future<List<ChatMessage>> getMessages(
    String conversationId, {
    int limit = _messagePageSize,
    QueryDocumentSnapshot<Map<String, dynamic>>? beforeDocument,
  }) async {
    Query<Map<String, dynamic>> query = _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit);
    if (beforeDocument != null) {
      query = query.startAfterDocument(beforeDocument);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map((document) => ChatMessage.fromFirestore(document, conversationId))
        .toList()
        .reversed
        .toList();
  }

  Stream<List<ChatMessage>> watchRecentMessages(String conversationId) =>
      _messages(conversationId)
          .orderBy('createdAt')
          .orderBy(FieldPath.documentId)
          .limitToLast(100)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      ChatMessage.fromFirestore(document, conversationId),
                )
                .toList(),
          );

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
    required String clientId,
    ChatReply? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw StateError('Message cannot be empty');
    if (trimmed.length > ChatFeatures.maxTextLength) {
      throw ArgumentError.value(
        text.length,
        'text',
        'Maximum length is ${ChatFeatures.maxTextLength}',
      );
    }
    return _insertMessage(
      conversationId: conversationId,
      clientId: clientId,
      content: trimmed,
      replyTo: replyTo,
    );
  }

  /// A sticker from a pack bundled in the app: no upload, only the id, so the
  /// message costs one document write and both sides render the same asset.
  Future<ChatMessage> sendSticker({
    required String conversationId,
    required String stickerId,
    required String clientId,
    ChatReply? replyTo,
  }) {
    if (!ChatFeatures.anyStickerSource) {
      throw StateError('Stickers are disabled');
    }
    return _insertMessage(
      conversationId: conversationId,
      clientId: clientId,
      type: ChatMessageType.sticker,
      stickerId: stickerId,
      replyTo: replyTo,
    );
  }

  /// Uploads [draft] and writes the message that points at the uploaded
  /// object, or at the draft's own url when the type needs no upload.
  ///
  /// [onProgress] receives 0..1 while the file travels and [controller] can
  /// abort a running upload. Anything that fails after the upload — a write the
  /// rules refuse included — deletes the object again, so an abandoned send
  /// leaves no billable file behind.
  Future<ChatMessage> sendMedia({
    required String conversationId,
    required ChatAttachmentDraft draft,
    required String clientId,
    ChatReply? replyTo,
    ChatUploadController? controller,
    void Function(double fraction)? onProgress,
  }) async {
    final sized = await draft.withMeasuredSize();
    final rejection = chatMediaRejection(sized);
    if (rejection != null) throw rejection;
    if (!sized.needsUpload) {
      return _insertMessage(
        conversationId: conversationId,
        clientId: clientId,
        content: sized.caption ?? '',
        type: sized.type,
        mediaPath: sized.localPath,
        replyTo: replyTo,
      );
    }
    final senderId = _me;
    final path = sized.storagePath(
      conversationId: conversationId,
      senderId: senderId,
      clientId: clientId,
    );
    final poster = sized.thumbnailPath;
    final posterPath = poster == null
        ? null
        : sized.thumbnailStoragePath(
            conversationId: conversationId,
            senderId: senderId,
            clientId: clientId,
          );
    final reference = _storage.ref(path);
    final posterReference = posterPath == null
        ? null
        : _storage.ref(posterPath);
    try {
      await _upload(
        reference,
        file: File(sized.localPath),
        contentType: sized.contentType,
        controller: controller,
        onProgress: onProgress,
      );
      if (poster != null && posterReference != null) {
        // The poster is a few dozen kilobytes, so it gets no separate progress
        // of its own; it does share the cancel button with the clip.
        await _upload(
          posterReference,
          file: File(poster),
          contentType: chatMediaThumbnailContentType,
          controller: controller,
        );
      }
      return await _insertMessage(
        conversationId: conversationId,
        clientId: clientId,
        content: sized.caption ?? '',
        type: sized.type,
        mediaPath: path,
        thumbUrl: posterPath,
        // Only a document is named to the receiver; a photo's staging name
        // would read as noise under the bubble.
        fileName: sized.type == ChatMessageType.file ? sized.fileName : null,
        fileSize: sized.byteSize,
        durationMs: _durationWithinRules(sized.durationMs),
        replyTo: replyTo,
      );
    } catch (error, stackTrace) {
      await _discardUpload(reference, sized.type);
      final posterUpload = posterReference;
      if (posterUpload != null) {
        await _discardUpload(posterUpload, ChatMessageType.image);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Removes an object that no message ended up pointing at. The removal is
  /// best effort: the send already failed, and a second failure here must not
  /// replace the reason the user was about to be told.
  Future<void> _discardUpload(Reference reference, ChatMessageType type) async {
    try {
      await reference.delete();
    } catch (cleanupError, cleanupStackTrace) {
      _logFailure(
        'remove an unreferenced uploaded chat ${type.wireValue}',
        cleanupError,
        cleanupStackTrace,
      );
    }
  }

  /// Runs the upload to completion, reporting progress when the caller wants
  /// it. Cancelling makes `await task` throw, so the caller's cleanup runs and
  /// no message is written for half-travelled bytes.
  Future<void> _upload(
    Reference reference, {
    required File file,
    required String contentType,
    ChatUploadController? controller,
    void Function(double fraction)? onProgress,
  }) async {
    final task = reference.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    controller?.attach(task);
    StreamSubscription<TaskSnapshot>? progress;
    try {
      if (onProgress != null) {
        progress = task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes <= 0) return;
          onProgress(
            (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
          );
        });
      }
      await task;
    } finally {
      await progress?.cancel();
      controller?.detach();
    }
  }

  /// `firestore.rules` refuses a `durationMs` above ten minutes, so a longer
  /// clip is sent without the label instead of being denied outright.
  static int? _durationWithinRules(int? durationMs) =>
      durationMs != null && durationMs <= chatMediaMaxDurationMs
      ? durationMs
      : null;

  /// The url a bubble or a player uses for a Storage object — or the object
  /// itself when the sender wrote a public url, which is what a GIF does.
  Future<String> getMediaUrl(String pathOrUrl) {
    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority) {
      return Future.value(pathOrUrl);
    }
    return _storage.ref(pathOrUrl).getDownloadURL();
  }

  /// Brings a received attachment down to this device and returns the path it
  /// landed on, so a document can be opened in another app and a clip can be
  /// replayed without spending a download on every scroll.
  ///
  /// The file lives in the app's own folder under the sender's object name,
  /// which is unique per message, so the same message tapped twice reuses what
  /// is already there instead of travelling the bytes again.
  Future<String> saveMediaToFile({
    required String mediaPath,
    required String fileName,
    void Function(double fraction)? onProgress,
  }) async {
    final url = await getMediaUrl(mediaPath);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath) {
      throw StateError('Nothing to download at $mediaPath');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final folder =
        '${supportDirectory.path}/chat-media/'
        '${mediaPath.split('/').last}';
    final target = File('$folder/${chatSafeReceivedName(fileName)}');
    if (await target.exists() && await target.length() > 0) {
      onProgress?.call(1);
      return target.path;
    }
    await target.parent.create(recursive: true);
    return _writeDownload(uri, target, onProgress);
  }

  Future<String> _writeDownload(
    Uri uri,
    File target,
    void Function(double fraction)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw StateError('Download failed with code ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null && total != null && total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
      return target.path;
    } catch (error) {
      // A half-written file opens as garbage in another app, so it goes.
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      Error.throwWithStackTrace(error, StackTrace.current);
    } finally {
      client.close();
    }
  }

  Future<ChatMessage> queueMessage({
    required String conversationId,
    required String text,
    required String clientId,
    ChatAttachmentDraft? attachment,
    String? stickerId,
    ChatReply? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachment == null && stickerId == null) {
      throw StateError('Message cannot be empty');
    }
    final staged = attachment == null
        ? null
        : await _stage(attachment.copyWith(caption: trimmed), clientId);
    if (staged != null) {
      final rejection = chatMediaRejection(staged);
      if (rejection != null) throw rejection;
    }
    final entry = <String, dynamic>{
      'client_id': clientId,
      'conversation_id': conversationId,
      'sender_id': _me,
      'content': trimmed,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'state': 'queued',
      if (staged != null) ...staged.toQueueFields(),
      // A bundled sticker is only an id, so the queue can carry it whole.
      'sticker_id': ?stickerId,
      // The quote travels with the queued send, so a reply typed offline still
      // arrives as a reply once the network comes back.
      if (replyTo != null) 'reply_to': replyTo.toMap(),
    };
    await _pendingQueue.enqueue(entry);
    return ChatMessage.fromPending(entry);
  }

  /// Copies a picked attachment into the pending folder so a restart still
  /// finds it, and returns the draft that points at the copy. A queued GIF has
  /// no file to keep and comes back untouched.
  Future<ChatAttachmentDraft> _stage(
    ChatAttachmentDraft draft,
    String clientId,
  ) async {
    if (!draft.needsUpload) return draft;
    final supportDirectory = await getApplicationSupportDirectory();
    final pendingDirectory = Directory('${supportDirectory.path}/pending-chat');
    await pendingDirectory.create(recursive: true);
    final target = File(
      '${pendingDirectory.path}/${draft.storageObjectName(clientId)}',
    );
    await _copyInto(target, File(draft.localPath));
    final poster = draft.thumbnailPath;
    String? stagedPoster;
    if (poster != null) {
      // The poster travels with the clip, so a video queued without a network
      // still arrives with a picture once the bytes can move.
      final posterTarget = File(
        '${pendingDirectory.path}/'
        '$clientId$chatMediaThumbnailSuffix.jpg',
      );
      await _copyInto(posterTarget, File(poster));
      stagedPoster = posterTarget.path;
    }
    return draft.copyWith(
      localPath: target.path,
      byteSize: await target.length(),
      thumbnailPath: stagedPoster,
    );
  }

  Future<void> _copyInto(File target, File source) async {
    if (source.path == target.path) return;
    await source.copy(target.path);
  }

  Future<List<ChatMessage>> getPendingMessages(String conversationId) async {
    final userId = _me;
    return (await _pendingQueue.read())
        .where(
          (entry) =>
              entry['sender_id'] == userId &&
              entry['conversation_id'] == conversationId,
        )
        .map(ChatMessage.fromPending)
        .toList();
  }

  Future<List<ChatMessage>> flushPendingMessages() async {
    final userId = _me;
    await _pendingQueue.cleanupOrphanedFiles();
    return _pendingQueue.runExclusive((transaction) async {
      final sent = <ChatMessage>[];
      for (var index = 0; index < transaction.entries.length; index++) {
        final entry = transaction.entries[index];
        if (!isReadyToSend(entry, senderId: userId)) continue;
        entry['state'] = 'sending';
        entry.remove('next_attempt_at');
        await transaction.save();

        ChatAttachmentDraft? draft;
        try {
          final conversationId = entry['conversation_id'] as String;
          final clientId = entry['client_id'] as String;
          final replyTo = ChatReply.fromData(
            entry['reply_to'] as Map<String, dynamic>?,
          );
          draft = ChatAttachmentDraft.fromQueueFields(entry);
          final stickerId = entry['sticker_id'] is String
              ? entry['sticker_id'] as String
              : null;
          final message = stickerId != null
              ? await sendSticker(
                  conversationId: conversationId,
                  stickerId: stickerId,
                  clientId: clientId,
                  replyTo: replyTo,
                )
              : draft == null
              ? await _insertMessage(
                  conversationId: conversationId,
                  clientId: clientId,
                  content: entry['content'] as String? ?? '',
                  replyTo: replyTo,
                )
              : await sendMedia(
                  conversationId: conversationId,
                  draft: draft,
                  clientId: clientId,
                  replyTo: replyTo,
                );
          sent.add(message);
          transaction.entries.removeAt(index);
          index--;
          await transaction.save();
          await _deleteStagedFile(draft);
        } catch (error, stackTrace) {
          _logFailure('flush a queued chat message', error, stackTrace);
          final failure = classifyPendingQueueFailure(error);
          if (failure == PendingQueueFailure.permanent) {
            entry['state'] = 'failed';
            entry.remove('next_attempt_at');
          } else {
            final attempts = nextAttemptCount(entry['attempts']);
            entry['state'] = 'queued';
            entry['attempts'] = attempts;
            entry['next_attempt_at'] = DateTime.now()
                .add(retryBackoff(attempts))
                .toIso8601String();
          }
          await transaction.save();
        }
      }
      return sent;
    });
  }

  /// Removes the private copies the queue kept for an upload that is now either
  /// sent or doomed — a clip and the poster staged beside it count as two. The
  /// original file in the gallery is never touched.
  Future<void> _deleteStagedFile(ChatAttachmentDraft? draft) async {
    if (draft == null || !draft.needsUpload) return;
    final poster = draft.thumbnailPath;
    for (final path in [draft.localPath, ?poster]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error, stackTrace) {
        _logFailure(
          'delete an uploaded pending chat attachment',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<List<ChatMessage>> retryPendingMessage(String clientId) async {
    await _pendingQueue.setStateFor(
      clientId: clientId,
      senderId: _me,
      state: 'queued',
    );
    return flushPendingMessages();
  }

  /// Forgets a queued or failed message: drops the local queue entry and, in
  /// case the transaction had already reached Firestore, deletes that document
  /// too. Only the sender can do this (see firestore.rules), so anything the
  /// other side already received stays in their copy of the thread.
  Future<void> deleteMessage({
    required String conversationId,
    required String clientId,
  }) async {
    await _pendingQueue.delete(clientId: clientId, senderId: _me);
    await _messages(conversationId).doc(clientId).delete();
  }

  /// Hide a message on this device only. The rules let either member add only
  /// themself to `deletedFor`, so the other side keeps seeing it — which is why
  /// re-adding an id that already contains me is skipped instead of written.
  Future<void> deleteForMe({
    required String conversationId,
    required ChatMessage message,
  }) async {
    if (message.deletedFor.contains(_me)) return;
    await _messages(conversationId).doc(message.id).update({
      'deletedFor': FieldValue.arrayUnion([_me]),
    });
  }

  /// The sender's "delete for everyone": one flag on their own document, which
  /// both sides render as a tombstone. The rules allow it once and never let it
  /// change any other field.
  Future<void> deleteForEveryone({
    required String conversationId,
    required String messageId,
  }) async {
    await _messages(conversationId)
        .doc(messageId)
        .update({'deletedForEveryone': true});
  }

  /// Writes my typing flag, and nothing else. The rules refuse a write that
  /// moves the other participant's flag, so a client can only claim to be
  /// typing.
  Future<void> setTyping(String conversationId, bool isTyping) async {
    await _conversations.doc(conversationId).update({'typing.$_me': isTyping});
  }

  /// Whether the other participant has their typing flag set. One document
  /// listener, not a thread listener, so the chat screen does not pay for it
  /// twice.
  Stream<bool> watchOtherTyping(
    String conversationId, {
    required String otherUserId,
  }) => _conversations.doc(conversationId).snapshots().map((snapshot) {
    final typing = snapshot.data()?['typing'] as Map<String, dynamic>?;
    return typing?[otherUserId] == true;
  });

  Future<void> markMessagesRead(String conversationId) async {
    final userId = _me;
    // Every message this app writes carries recipientId (see _insertMessage) and
    // the rules now require it, so the second "legacy" scan without that filter
    // was reading up to 100 documents of the other side on every chat open.
    final messages = await _messages(conversationId)
        .where('recipientId', isEqualTo: userId)
        .where('status', whereIn: const ['sent', 'delivered'])
        .orderBy('createdAt', descending: true)
        .limit(_statusPageSize)
        .get();
    await _updateMessageStatuses(
      messages.docs,
      userId: userId,
      targetStatus: 'read',
    );
    await _conversations.doc(conversationId).update({
      'unreadCounts.$userId': 0,
    });
  }

  Future<void> markReceivedMessagesDelivered() async {
    final userId = _me;
    // Ordered by the newest activity, so the sweep spends its 50 reads on the
    // conversations that can actually hold unread mail.
    final conversations = await _conversations
        .where('members', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .limit(conversationPageSize)
        .get();
    for (final conversation in conversations.docs) {
      final unreadCounts =
          conversation.data()['unreadCounts'] as Map<String, dynamic>? ?? {};
      if (_asInt(unreadCounts[userId]) <= 0) continue;

      final undelivered = await _messages(conversation.id)
          .where('recipientId', isEqualTo: userId)
          .where('status', isEqualTo: 'sent')
          .orderBy('createdAt', descending: true)
          .limit(_statusPageSize)
          .get();
      await _updateMessageStatuses(
        undelivered.docs,
        userId: userId,
        targetStatus: 'delivered',
      );
    }
  }

  Future<void> _updateMessageStatuses(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents, {
    required String userId,
    required String targetStatus,
  }) async {
    for (var start = 0; start < documents.length; start += 450) {
      final chunk = documents.skip(start).take(450).toList();
      final batch = _firestore.batch();
      for (final document in chunk) {
        batch.update(document.reference, {'status': targetStatus});
      }
      try {
        await batch.commit();
      } catch (error, stackTrace) {
        _logFailure('batch-update message statuses', error, stackTrace);
        for (final document in chunk) {
          await _updateMessageStatusIfAllowed(
            document.reference,
            userId: userId,
            targetStatus: targetStatus,
          );
        }
      }
    }
  }

  Future<void> _updateMessageStatusIfAllowed(
    DocumentReference<Map<String, dynamic>> reference, {
    required String userId,
    required String targetStatus,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null ||
          data['senderId'] == userId ||
          !canMoveStatus(
            from: data['status'] as String? ?? 'sent',
            to: targetStatus,
          )) {
        return;
      }
      transaction.update(reference, {'status': targetStatus});
    });
  }

  /// The Firestore document for one outgoing message.
  ///
  /// It mirrors the `messages/{messageId}` create rule key for key: optional
  /// fields are left out entirely rather than written as null, because the rule
  /// validates each one that is present. `createdAt` is a server timestamp so
  /// the thread order cannot be forged from the device.
  @visibleForTesting
  static Map<String, dynamic> messageFields({
    required String senderId,
    required String recipientId,
    required String clientId,
    required String content,
    ChatMessageType type = ChatMessageType.text,
    String? mediaPath,
    String? thumbUrl,
    String? fileName,
    int? fileSize,
    int? durationMs,
    String? stickerId,
    ChatReply? replyTo,
  }) {
    final fields = <String, dynamic>{
      'senderId': senderId,
      'recipientId': recipientId,
      'clientId': clientId,
      'content': content,
      'mediaUrl': mediaPath,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'sent',
      'type': type.wireValue,
    };
    if (thumbUrl != null) fields['thumbUrl'] = thumbUrl;
    if (fileName != null) fields['fileName'] = fileName;
    if (fileSize != null) fields['fileSize'] = fileSize;
    if (durationMs != null) fields['durationMs'] = durationMs;
    if (stickerId != null) fields['stickerId'] = stickerId;
    if (replyTo != null) fields['replyTo'] = replyTo.toMap();
    return fields;
  }

  /// The conversation-list fields for the message that was just written. The
  /// preview text stays null for a message with no text; the list shows the
  /// type label from [ChatConversationPreview.lastMessageType] instead, so no
  /// English word is ever stored.
  @visibleForTesting
  static Map<String, dynamic> conversationFields({
    required String recipientId,
    required String content,
    required ChatMessageType type,
    required String senderId,
  }) => {
    'lastMessageContent': content.isEmpty ? null : content,
    'lastMessageAt': FieldValue.serverTimestamp(),
    'lastMessageType': type.wireValue,
    'lastSenderId': senderId,
    'unreadCounts.$recipientId': FieldValue.increment(1),
  };

  Future<ChatMessage> _insertMessage({
    required String conversationId,
    required String clientId,
    String content = '',
    ChatMessageType type = ChatMessageType.text,
    String? mediaPath,
    String? thumbUrl,
    String? fileName,
    int? fileSize,
    int? durationMs,
    String? stickerId,
    ChatReply? replyTo,
  }) async {
    final senderId = _me;
    final trimmedContent = content.trim();
    if (trimmedContent.length > ChatFeatures.maxTextLength) {
      throw ArgumentError.value(
        trimmedContent.length,
        'content',
        'Maximum length is ${ChatFeatures.maxTextLength}',
      );
    }
    if (trimmedContent.isEmpty && !type.hasVisiblePayload) {
      throw StateError('Message must contain text or an attachment');
    }
    final conversation = _conversations.doc(conversationId);
    final message = _messages(conversationId).doc(clientId);
    return _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(message);
      if (existing.exists) {
        return ChatMessage.fromData(
          id: existing.id,
          conversationId: conversationId,
          data: existing.data() ?? const {},
        );
      }
      final conversationSnapshot = await transaction.get(conversation);
      final data = conversationSnapshot.data();
      final members = (data?['members'] as List<dynamic>? ?? []).cast<String>();
      if (!conversationSnapshot.exists || !members.contains(senderId)) {
        throw StateError('Conversation not found or access denied');
      }
      final recipientId = recipientOf(members, senderId);
      if (recipientId == null) {
        throw StateError('Conversation must have two members');
      }

      final createdAt = DateTime.now();
      transaction.set(
        message,
        messageFields(
          senderId: senderId,
          recipientId: recipientId,
          clientId: clientId,
          content: trimmedContent,
          type: type,
          mediaPath: mediaPath,
          thumbUrl: thumbUrl,
          fileName: fileName,
          fileSize: fileSize,
          durationMs: durationMs,
          stickerId: stickerId,
          replyTo: replyTo,
        ),
      );
      transaction.update(
        conversation,
        conversationFields(
          recipientId: recipientId,
          content: trimmedContent,
          type: type,
          senderId: senderId,
        ),
      );
      return ChatMessage(
        id: clientId,
        conversationId: conversationId,
        senderId: senderId,
        content: trimmedContent,
        mediaPath: mediaPath,
        clientId: clientId,
        createdAt: createdAt,
        status: 'sent',
        type: type,
        thumbUrl: thumbUrl,
        fileName: fileName,
        fileSize: fileSize,
        durationMs: durationMs,
        stickerId: stickerId,
        replyTo: replyTo,
      );
    });
  }

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
