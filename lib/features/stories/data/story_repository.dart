import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// A 24-hour story. Expiry is derived from [createdAt], which the server writes,
/// so a client cannot extend its own story by faking a timestamp.
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.username,
    required this.fullName,
    required this.mediaUrl,
    required this.createdAt,
    this.avatarUrl,
  });

  final String id;
  final String authorId;
  final String username;
  final String fullName;
  final String mediaUrl;
  final DateTime createdAt;
  final String? avatarUrl;

  static const lifetime = Duration(hours: 24);

  String get displayName => fullName.isNotEmpty ? fullName : username;

  DateTime get expiresAt => createdAt.add(lifetime);

  factory Story.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final timestamp = data['createdAt'];
    return Story(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      username: data['username'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String? ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      avatarUrl: data['avatarUrl'] as String?,
    );
  }
}

/// One user's stories, oldest first, as shown by one avatar in the rail.
class StoryGroup {
  const StoryGroup({required this.authorId, required this.stories});

  final String authorId;
  final List<Story> stories;

  String get username => stories.first.username;
  String get fullName => stories.first.fullName;
  String? get avatarUrl => stories.first.avatarUrl;
  String get displayName => stories.first.displayName;
}

class StoryRepository {
  StoryRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  static const storyPageSize = 60;

  /// Who watched a story, and how many the delete query reads at a time. The
  /// `viewers` rules cap a list query at this same number.
  static const viewerPageSize = 200;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  String get _userId {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw StateError('Sign in to view stories');
    return userId;
  }

  CollectionReference<Map<String, dynamic>> get _stories =>
      _firestore.collection('stories');

  /// Stories created in the last 24 hours, newest first, grouped per author.
  Stream<List<StoryGroup>> watchActiveStoryGroups() {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(Story.lifetime));
    return _stories
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .limit(storyPageSize)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final stories = snapshot.docs
              .map(Story.fromFirestore)
              .where((story) => story.mediaUrl.isNotEmpty)
              // The query cutoff is fixed when the subscription starts, so drop
              // stories that expired while this stream stayed open.
              .where((story) => now.isBefore(story.expiresAt))
              .toList();
          final groups = <String, List<Story>>{};
          for (final story in stories.reversed) {
            groups.putIfAbsent(story.authorId, () => []).add(story);
          }
          // Authors with the freshest story come first.
          final ordered = groups.values.toList()
            ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
          return ordered
              .map(
                (items) =>
                    StoryGroup(authorId: items.first.authorId, stories: items),
              )
              .toList(growable: false);
        });
  }

  Future<Story> createStory({
    required Uint8List bytes,
    required String contentType,
    required String extension,
  }) async {
    final userId = _userId;
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Empty story media');
    }
    final profile = await _firestore
        .collection('publicProfiles')
        .doc(userId)
        .get(GetOptions(source: Source.server));
    final data = profile.data();
    if (data == null) {
      throw StateError('Complete your profile before posting a story');
    }
    final reference = _stories.doc();
    final mediaUrl = await _storage
        .ref('stories/$userId/${reference.id}.$extension')
        .putData(bytes, SettableMetadata(contentType: contentType))
        .then((task) => task.ref.getDownloadURL());
    final payload = <String, dynamic>{
      'authorId': userId,
      'username': data['username'] as String? ?? '',
      'fullName': data['fullName'] as String? ?? '',
      'avatarUrl': data['avatarUrl'],
      'mediaUrl': mediaUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await reference.set(payload);
    } catch (error, stackTrace) {
      _logFailure('remove story media that was never saved', error, stackTrace);
      await _deleteMedia(mediaUrl);
      rethrow;
    }
    return Story(
      id: reference.id,
      authorId: userId,
      username: payload['username'] as String,
      fullName: payload['fullName'] as String,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now(),
      avatarUrl: data['avatarUrl'] as String?,
    );
  }

  Future<void> deleteStory(Story story) async {
    final reference = _stories.doc(story.id);
    // The audience goes first: its rules read the parent story to decide who is
    // allowed to write, so once the story is gone every viewer document becomes
    // undeletable and stays in the database forever.
    await _clearViewers(reference);
    // Remove the document before the media: a leftover file is recoverable, a
    // story that points at deleted media is not.
    await reference.delete();
    await _deleteMedia(story.mediaUrl);
  }

  /// Deletes who watched this story, `viewerPageSize` documents at a time.
  Future<void> _clearViewers(
    DocumentReference<Map<String, dynamic>> story,
  ) async {
    final viewers = story.collection('viewers');
    while (true) {
      final page = await viewers.limit(viewerPageSize).get();
      if (page.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final document in page.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
      if (page.docs.length < viewerPageSize) return;
    }
  }

  Future<void> _deleteMedia(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (error, stackTrace) {
      _logFailure('remove story media', error, stackTrace);
      rethrow;
    }
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Unable to $operation: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
