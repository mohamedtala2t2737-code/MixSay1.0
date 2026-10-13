import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.username,
    required this.fullName,
    required this.caption,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    required this.artworkVariant,
    required this.isLiked,
    this.avatarUrl,
    this.mediaUrl,
    this.mediaType = 'none',
  });

  final String id;
  final String authorId;
  final String username;
  final String fullName;
  final String caption;
  final int likesCount;
  final int commentsCount;
  final DateTime? createdAt;
  final int artworkVariant;
  final bool isLiked;
  final String? avatarUrl;
  final String? mediaUrl;
  final String mediaType;

  String get displayName => fullName.isNotEmpty ? fullName : username;

  factory FeedPost.fromFirestore({
    required QueryDocumentSnapshot<Map<String, dynamic>> document,
    required bool isLiked,
  }) {
    final data = document.data();
    final timestamp = data['createdAt'];
    return FeedPost(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      username: data['username'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      caption: data['caption'] as String? ?? '',
      likesCount: _safeInt(data['likesCount']),
      commentsCount: _safeInt(data['commentsCount']),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      artworkVariant: document.id.hashCode.abs() % 5,
      isLiked: isLiked,
      avatarUrl: data['avatarUrl'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
      mediaType: data['mediaType'] as String? ?? 'none',
    );
  }
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.authorId,
    required this.username,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String username;
  final String content;
  final DateTime? createdAt;

  factory FeedComment.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final timestamp = data['createdAt'];
    return FeedComment(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      username: data['username'] as String? ?? '',
      content: data['content'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

class FeedRepository {
  FeedRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  static const postPageSize = 30;
  static const commentPageSize = 50;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  String get _userId {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw StateError('Sign in to view the MixSay feed');
    return userId;
  }

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  Stream<List<FeedPost>> watchPosts() {
    final userId = _userId;
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(postPageSize)
        .snapshots()
        .asyncMap((snapshot) async {
          return Future.wait(
            snapshot.docs.map((document) async {
              try {
                final like = await document.reference
                    .collection('likes')
                    .doc(userId)
                    .get();
                return FeedPost.fromFirestore(
                  document: document,
                  isLiked: like.exists,
                );
              } catch (error, stackTrace) {
                _logFailure('load the current user post reaction', error, stackTrace);
                rethrow;
              }
            }),
          );
        });
  }

  Stream<List<FeedComment>> watchComments(String postId) => _posts
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(commentPageSize)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(FeedComment.fromFirestore).toList(growable: false),
      );

  Future<void> toggleLike({
    required FeedPost post,
    required String username,
  }) async {
    final userId = _userId;
    final postReference = _posts.doc(post.id);
    final likeReference = postReference.collection('likes').doc(userId);
    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postReference);
      final likeSnapshot = await transaction.get(likeReference);
      if (!postSnapshot.exists) throw StateError('Post no longer exists');
      final likeCount = _safeInt(postSnapshot.data()?['likesCount']);
      if (likeSnapshot.exists) {
        transaction.delete(likeReference);
        transaction.update(postReference, {
          'likesCount': likeCount > 0 ? likeCount - 1 : 0,
        });
      } else {
        transaction.set(likeReference, {
          'authorId': userId,
          'username': username,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postReference, {'likesCount': likeCount + 1});
      }
    });
  }

  Future<void> addComment({
    required String postId,
    required String username,
    required String content,
  }) async {
    final userId = _userId;
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw ArgumentError.value(content, 'content', 'Comment must be 1-1000 characters');
    }
    final postReference = _posts.doc(postId);
    final commentReference = postReference.collection('comments').doc();
    await _firestore.runTransaction((transaction) async {
      final post = await transaction.get(postReference);
      if (!post.exists) throw StateError('Post no longer exists');
      transaction.set(commentReference, {
        'authorId': userId,
        'username': username,
        'content': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(postReference, {
        'commentsCount': _safeInt(post.data()?['commentsCount']) + 1,
      });
    });
  }

  Future<void> createPost({
    required String caption,
    String? mediaUrl,
    String mediaType = 'none',
  }) async {
    final userId = _userId;
    final trimmedCaption = caption.trim();
    if (trimmedCaption.length > 2000) {
      throw ArgumentError.value(caption, 'caption', 'Maximum length is 2000');
    }
    if (trimmedCaption.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) {
      throw ArgumentError('A post must contain text or media');
    }
    if (!const {'none', 'image', 'video'}.contains(mediaType)) {
      throw ArgumentError.value(mediaType, 'mediaType');
    }
    final profile = await _firestore.collection('publicProfiles').doc(userId).get();
    final data = profile.data();
    if (!profile.exists || data == null) {
      throw StateError('Complete your profile before creating a post');
    }
    await _posts.add({
      'authorId': userId,
      'username': data['username'] as String? ?? '',
      'fullName': data['fullName'] as String? ?? '',
      'avatarUrl': data['avatarUrl'],
      'caption': trimmedCaption,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'likesCount': 0,
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadPostMedia({
    required String postId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
  }) async {
    final userId = _userId;
    final reference = _storage.ref('posts/$userId/$postId.$extension');
    await reference.putData(bytes, SettableMetadata(contentType: contentType));
    return reference.getDownloadURL();
  }

  Future<void> deleteUnpublishedMedia(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (error, stackTrace) {
      _logFailure('remove unlinked post media', error, stackTrace);
      rethrow;
    }
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Unable to $operation: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

int _safeInt(dynamic value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
