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

  /// postId -> whether the current user liked it. The like document id is the
  /// liker's uid, so a page of 30 posts used to cost 30 reads on every snapshot.
  final Map<String, bool> _likedByPostCache = {};
  String? _cachedForUserId;

  Stream<List<FeedPost>> watchPosts() {
    final userId = _userId;
    if (_cachedForUserId != userId) {
      _likedByPostCache.clear();
      _cachedForUserId = userId;
    }
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(postPageSize)
        .snapshots()
        .asyncMap((snapshot) async {
          final visibleIds = snapshot.docs
              .map((document) => document.id)
              .toSet();
          _likedByPostCache.removeWhere((id, _) => !visibleIds.contains(id));
          final unknown = snapshot.docs
              .where((document) => !_likedByPostCache.containsKey(document.id))
              .toList(growable: false);
          if (unknown.isNotEmpty) {
            await Future.wait(
              unknown.map((document) async {
                try {
                  final like = await document.reference
                      .collection('likes')
                      .doc(userId)
                      .get();
                  _likedByPostCache[document.id] = like.exists;
                } catch (error, stackTrace) {
                  _logFailure(
                    'load the current user post reaction',
                    error,
                    stackTrace,
                  );
                  rethrow;
                }
              }),
            );
          }
          return snapshot.docs
              .map(
                (document) => FeedPost.fromFirestore(
                  document: document,
                  isLiked: _likedByPostCache[document.id] ?? false,
                ),
              )
              .toList(growable: false);
        });
  }

  Stream<List<FeedPost>> watchPostsByAuthor(String authorId) => _posts
      .where('authorId', isEqualTo: authorId)
      .orderBy('createdAt', descending: true)
      .limit(postPageSize)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) =>
                  FeedPost.fromFirestore(document: document, isLiked: false),
            )
            .toList(growable: false),
      );

  Stream<List<FeedComment>> watchComments(String postId) => _posts
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(commentPageSize)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(FeedComment.fromFirestore)
            .toList(growable: false),
      );

  /// The acting user's public profile. Firestore rules stamp `username` into
  /// posts, likes and comments, so it is read from the server instead of from a
  /// UI cache that may still be loading.
  Future<Map<String, dynamic>> _currentProfile(String userId) async {
    final profile = await _firestore
        .collection('publicProfiles')
        .doc(userId)
        .get();
    final data = profile.data();
    if (!profile.exists || data == null) {
      throw StateError('Complete your profile before using the MixSay feed');
    }
    return data;
  }

  Future<void> toggleLike({required FeedPost post}) async {
    final userId = _userId;
    final username = _profileUsername(await _currentProfile(userId));
    final postReference = _posts.doc(post.id);
    final likeReference = postReference.collection('likes').doc(userId);
    var nowLiked = false;
    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postReference);
      final likeSnapshot = await transaction.get(likeReference);
      if (!postSnapshot.exists) throw StateError('Post no longer exists');
      if (likeSnapshot.exists) {
        transaction.delete(likeReference);
        transaction.update(postReference, {
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        transaction.set(likeReference, {
          'authorId': userId,
          'username': username,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postReference, {
          'likesCount': FieldValue.increment(1),
        });
        nowLiked = true;
      }
    });
    _likedByPostCache[post.id] = nowLiked;
  }

  Future<void> addComment({
    required String postId,
    required String content,
  }) async {
    final userId = _userId;
    final username = _profileUsername(await _currentProfile(userId));
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw ArgumentError.value(
        content,
        'content',
        'Comment must be 1-1000 characters',
      );
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
        'commentsCount': FieldValue.increment(1),
      });
    });
  }

  /// Author-only (see the `posts/{postId}` delete rule). Media is removed after
  /// the document so a failed storage delete leaves an orphan file, not a
  /// post whose image is gone.
  Future<void> deletePost(FeedPost post) async {
    await _posts.doc(post.id).delete();
    final url = post.mediaUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
    } catch (error, stackTrace) {
      _logFailure('remove deleted post media', error, stackTrace);
    }
  }

  Future<void> createPost({
    required String postId,
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
    final profile = await _currentProfile(userId);
    await _posts.doc(postId).set({
      'authorId': userId,
      'username': _profileUsername(profile),
      'fullName': profile['fullName'] as String? ?? '',
      'avatarUrl': profile['avatarUrl'],
      'caption': trimmedCaption,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'likesCount': 0,
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Id for a post that does not exist yet, so its media can be uploaded under
  /// a matching path before the document is written.
  String newPostId() => _posts.doc().id;

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

String _profileUsername(Map<String, dynamic> profile) {
  final username = profile['username'] as String? ?? '';
  if (username.isEmpty) {
    throw StateError('Complete your profile before using the MixSay feed');
  }
  return username;
}
