import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  });

  final String id;
  final String otherUserId;
  final String otherUsername;
  final String otherFullName;
  final String? otherAvatarUrl;
  final String? lastMessageContent;
  final DateTime? lastMessageAt;
  final int unreadCount;

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
  });

  final String conversationId;
  final String otherUserId;
  final String otherUsername;
  final String otherFullName;
  final String? otherAvatarUrl;
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
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaPath;
  final String? clientId;
  final String? localImagePath;
  final QueryDocumentSnapshot<Map<String, dynamic>>? documentSnapshot;
  final DateTime createdAt;
  final String status;

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
    );
  }

  factory ChatMessage.fromPending(Map<String, dynamic> entry) => ChatMessage(
    id: 'pending-${entry['client_id']}',
    conversationId: entry['conversation_id'] as String,
    senderId: entry['sender_id'] as String,
    content: entry['content'] as String? ?? '',
    mediaPath: entry['local_image_path'] as String?,
    clientId: entry['client_id'] as String,
    localImagePath: entry['local_image_path'] as String?,
    createdAt: DateTime.parse(entry['created_at'] as String),
    status: entry['state'] as String? ?? 'sending',
  );
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
  static const _conversationPageSize = 50;
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
        .limit(_conversationPageSize)
        .snapshots()
        .asyncMap((snapshot) async {
          final items = await Future.wait(
            snapshot.docs.map((document) async {
              final preview = ChatConversationPreview.fromFirestore(
                document,
                currentUserId,
              );
              try {
                final profile = await _getPublicProfile(preview.otherUserId);
                return preview.withPublicProfile(profile);
              } catch (error, stackTrace) {
                _logFailure(
                  'load a conversation member profile',
                  error,
                  stackTrace,
                );
                return preview;
              }
            }),
          );
          return items;
        });
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
    try {
      profile = await _getPublicProfile(otherUserId);
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
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw StateError('Message cannot be empty');
    if (trimmed.length > 4000) {
      throw ArgumentError.value(text.length, 'text', 'Maximum length is 4000');
    }
    return _insertMessage(
      conversationId: conversationId,
      clientId: clientId,
      content: trimmed,
    );
  }

  Future<ChatMessage> sendImage({
    required String conversationId,
    required Uint8List bytes,
    required String clientId,
  }) async {
    final senderId = _me;
    final path = 'chats/$conversationId/$senderId/$clientId.jpg';
    final imageReference = _storage.ref(path);
    try {
      await imageReference.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await _insertMessage(
        conversationId: conversationId,
        clientId: clientId,
        mediaPath: path,
      );
    } catch (error, stackTrace) {
      try {
        await imageReference.delete();
      } catch (cleanupError, cleanupStackTrace) {
        _logFailure(
          'remove an unreferenced uploaded chat image',
          cleanupError,
          cleanupStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<String> getImageUrl(String pathOrUrl) {
    final uri = Uri.tryParse(pathOrUrl);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority) {
      return Future.value(pathOrUrl);
    }
    return _storage.ref(pathOrUrl).getDownloadURL();
  }

  Future<ChatMessage> queueMessage({
    required String conversationId,
    required String text,
    required String clientId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw StateError('Message cannot be empty');
    final createdAt = DateTime.now().toUtc();
    final entry = <String, dynamic>{
      'client_id': clientId,
      'conversation_id': conversationId,
      'sender_id': _me,
      'content': trimmed,
      'created_at': createdAt.toIso8601String(),
      'state': 'queued',
    };
    await _pendingQueue.enqueue(entry);
    return ChatMessage.fromPending(entry);
  }

  Future<ChatMessage> queueImage({
    required String conversationId,
    required Uint8List bytes,
    required String clientId,
  }) async {
    final directory = await getApplicationSupportDirectory();
    final pendingDirectory = Directory('${directory.path}/pending-chat');
    await pendingDirectory.create(recursive: true);
    final imageFile = File('${pendingDirectory.path}/$clientId.jpg');
    await imageFile.writeAsBytes(bytes, flush: true);

    final entry = <String, dynamic>{
      'client_id': clientId,
      'conversation_id': conversationId,
      'sender_id': _me,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'local_image_path': imageFile.path,
      'state': 'queued',
    };
    await _pendingQueue.enqueue(entry);
    return ChatMessage.fromPending(entry);
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
    await _pendingQueue.cleanupOrphanedImages();
    return _pendingQueue.runExclusive((transaction) async {
      final sent = <ChatMessage>[];
      for (var index = 0; index < transaction.entries.length; index++) {
        final entry = transaction.entries[index];
        if (!isReadyToSend(entry, senderId: userId)) continue;
        entry['state'] = 'sending';
        entry.remove('next_attempt_at');
        await transaction.save();

        try {
          final conversationId = entry['conversation_id'] as String;
          final clientId = entry['client_id'] as String;
          final imagePath = entry['local_image_path'] as String?;
          final message = imagePath == null
              ? await _insertMessage(
                  conversationId: conversationId,
                  clientId: clientId,
                  content: entry['content'] as String? ?? '',
                )
              : await sendImage(
                  conversationId: conversationId,
                  bytes: await File(imagePath).readAsBytes(),
                  clientId: clientId,
                );
          sent.add(message);
          transaction.entries.removeAt(index);
          index--;
          await transaction.save();
          if (imagePath != null) {
            try {
              final file = File(imagePath);
              if (await file.exists()) await file.delete();
            } catch (error, stackTrace) {
              _logFailure(
                'delete an uploaded pending chat image',
                error,
                stackTrace,
              );
            }
          }
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
        .limit(_conversationPageSize)
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

  Future<ChatMessage> _insertMessage({
    required String conversationId,
    required String clientId,
    String? content,
    String? mediaPath,
  }) async {
    final senderId = _me;
    final trimmedContent = content?.trim() ?? '';
    if (trimmedContent.length > 4000) {
      throw ArgumentError.value(
        trimmedContent.length,
        'content',
        'Maximum length is 4000',
      );
    }
    if (trimmedContent.isEmpty && (mediaPath == null || mediaPath.isEmpty)) {
      throw StateError('Message must contain text or an image');
    }
    final conversation = _conversations.doc(conversationId);
    final message = _messages(conversationId).doc(clientId);
    return _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(message);
      if (existing.exists) {
        return ChatMessage(
          id: existing.id,
          conversationId: conversationId,
          senderId: existing.data()?['senderId'] as String? ?? senderId,
          content: existing.data()?['content'] as String? ?? '',
          mediaPath:
              existing.data()?['mediaPath'] as String? ??
              existing.data()?['mediaUrl'] as String?,
          clientId: clientId,
          createdAt: _dateTime(existing.data()?['createdAt']) ?? DateTime.now(),
          status: existing.data()?['status'] as String? ?? 'sent',
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
      transaction.set(message, {
        'senderId': senderId,
        'recipientId': recipientId,
        'clientId': clientId,
        'content': trimmedContent,
        'mediaUrl': mediaPath,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
      transaction.update(conversation, {
        'lastMessageContent': trimmedContent.isNotEmpty
            ? trimmedContent
            : 'Photo',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCounts.$recipientId': FieldValue.increment(1),
      });
      return ChatMessage(
        id: clientId,
        conversationId: conversationId,
        senderId: senderId,
        content: content ?? '',
        mediaPath: mediaPath,
        clientId: clientId,
        createdAt: createdAt,
        status: 'sent',
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
