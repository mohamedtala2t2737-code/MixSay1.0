import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:social_chat/core/errors/app_exceptions.dart';
import 'package:social_chat/core/utils/picked_media.dart';

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
    this.mediaUrls = const [],
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
  final List<String> mediaUrls;
  final String mediaType;

  String get displayName => fullName.isNotEmpty ? fullName : username;

  /// What the media slot paints. A post written before carousels existed only
  /// carries [mediaUrl], which becomes its single slide, so nothing old needs
  /// migrating to stay readable.
  List<String> get slides => mediaUrls.isNotEmpty
      ? mediaUrls
      : (mediaUrl == null || mediaUrl!.isEmpty
            ? const <String>[]
            : [mediaUrl!]);

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
      mediaUrls: _storedUrls(data['mediaUrls']),
      mediaType: data['mediaType'] as String? ?? 'none',
    );
  }

  /// Anything Firestore could hand back as a url list, reduced to the urls that
  /// can actually be loaded.
  static List<String> _storedUrls(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }
}

/// One page of an author's posts, plus what it takes to ask for the next one.
class FeedPostPage {
  const FeedPostPage({
    required this.posts,
    required this.hasMore,
    this.cursor,
  });

  final List<FeedPost> posts;

  /// A full page means the query had an answer for every slot, so more posts
  /// are probably waiting. A short page is the end of the list.
  final bool hasMore;

  /// The last document read, used as `startAfter` for the next page. Null only
  /// when the page came back empty.
  final DocumentSnapshot? cursor;
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

  /// One page of one author's posts of exactly one `mediaType`.
  ///
  /// The type filter runs on the server, not over a mixed page: filtering after
  /// reading would put fewer than 30 tiles on the wall whenever the newest posts
  /// are of another type, and the cursor would skip past the ones that matched.
  /// Needs the `authorId ASC, mediaType ASC, createdAt DESC` index declared in
  /// `firestore.indexes.json`; the emulator never complains about a missing one.
  Future<FeedPostPage> fetchPostsByAuthorAndType({
    required String authorId,
    required String mediaType,
    DocumentSnapshot? after,
    int limit = postPageSize,
  }) async {
    // `allow list: request.query.limit <= 30`, so a page is never asked for
    // larger than the wall's own size.
    Query<Map<String, dynamic>> query = _posts
        .where('authorId', isEqualTo: authorId)
        .where('mediaType', isEqualTo: mediaType)
        .orderBy('createdAt', descending: true);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.limit(limit).get();
    final documents = snapshot.docs;
    return FeedPostPage(
      posts: documents
          .map(
            (document) => FeedPost.fromFirestore(
              document: document,
              isLiked: false,
            ),
          )
          .toList(growable: false),
      hasMore: documents.length == limit,
      cursor: documents.isEmpty ? null : documents.last,
    );
  }

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
  /// post whose image is gone. A carousel's slides are deleted one by one:
  /// Firestore does not know about Storage, and one dead link must not stop the
  /// rest of the files from going.
  Future<void> deletePost(FeedPost post) async {
    await _posts.doc(post.id).delete();
    for (final url in post.slides) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (error, stackTrace) {
        _logFailure('remove deleted post media', error, stackTrace);
      }
    }
  }

  /// The slides a post is allowed to carry, ready to write.
  ///
  /// `firestore.rules` can inspect the count and the first slide only (the
  /// rules language has no list macro), so every other url is checked here,
  /// before the document is written.
  static List<String> validatedSlides(List<String> urls, String mediaType) {
    final slides = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    switch (mediaType) {
      case 'none':
        if (slides.isNotEmpty) {
          throw ArgumentError('A post without media cannot carry slides');
        }
        return const [];
      case 'video':
        if (slides.length != 1) {
          throw ArgumentError('A video post carries exactly one clip');
        }
        return slides;
      case 'image':
        if (slides.isEmpty || slides.length > maxPostSlides) {
          throw ArgumentError('An image post carries 1-$maxPostSlides photos');
        }
        return slides;
      default:
        throw ArgumentError.value(mediaType, 'mediaType');
    }
  }

  Future<void> createPost({
    required String postId,
    required String caption,
    List<String> mediaUrls = const [],
    String mediaType = 'none',
  }) async {
    final userId = _userId;
    final trimmedCaption = caption.trim();
    if (trimmedCaption.length > 2000) {
      throw ArgumentError.value(caption, 'caption', 'Maximum length is 2000');
    }
    final slides = validatedSlides(mediaUrls, mediaType);
    if (trimmedCaption.isEmpty && slides.isEmpty) {
      throw ArgumentError('A post must contain text or media');
    }
    final profile = await _currentProfile(userId);
    try {
      await _posts.doc(postId).set({
        'authorId': userId,
        'username': _profileUsername(profile),
        'fullName': profile['fullName'] as String? ?? '',
        'avatarUrl': profile['avatarUrl'],
        'caption': trimmedCaption,
        // Readers that only know the old field must still find a real image, so
        // it keeps naming the first slide.
        'mediaUrl': slides.isEmpty ? null : slides.first,
        // Written only for a real carousel. A single photo stays exactly the
        // document shape the currently deployed rules accept, so an un-deployed
        // rules update can never break the ordinary post path. The rules also
        // require `mediaType == 'image'` whenever this key is present.
        if (slides.length > 1) 'mediaUrls': slides,
        'mediaType': mediaType,
        'likesCount': 0,
        'commentsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (failure) {
      // A rejected write is the deployed rules refusing the document, not a
      // flaky connection. Say so: the alternative is the user retrying forever.
      if (failure.code == 'permission-denied') {
        throw const PostRejectedException();
      }
      rethrow;
    }
  }

  /// Id for a post that does not exist yet, so its media can be uploaded under
  /// a matching path before the document is written.
  String newPostId() => _posts.doc().id;

  /// Uploads the attached photo or clip under the author's own id and returns
  /// its download URL.
  ///
  /// The explicit `contentType` is not decoration: without it Storage infers
  /// `application/octet-stream` and `storage.rules` refuses the write. Videos
  /// stream from disk with `putFile` so a large clip never lands in the heap,
  /// and [onProgress] receives a 0..1 fraction while it goes.
  Future<String> uploadPostMedia({
    required String postId,
    required PickedPostMedia media,
    int slide = 0,
    void Function(double fraction)? onProgress,
  }) async {
    final userId = _userId;
    final name = slide == 0
        ? '$postId.${media.extension}'
        : '$postId-$slide.${media.extension}';
    final reference = _storage.ref('posts/$userId/$name');
    final metadata = SettableMetadata(contentType: media.contentType);
    final bytes = media.bytes;
    final task = bytes != null
        ? reference.putData(bytes, metadata)
        : reference.putFile(File(media.filePath!), metadata);

    final progress = onProgress == null
        ? null
        : task.snapshotEvents.listen((snapshot) {
            if (snapshot.totalBytes <= 0) return;
            onProgress(
              (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
            );
          });
    try {
      await task;
    } finally {
      await progress?.cancel();
    }
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
