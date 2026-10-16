import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// A person in the follow graph, ready to draw in a row.
class FollowedUser {
  const FollowedUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

/// A follower or following total. [capped] means the app read as many rows as
/// the rules allow and there may be more behind them.
class FollowCount {
  const FollowCount(this.value, {this.capped = false});

  final int value;
  final bool capped;

  String get label => capped ? '$value+' : '$value';
}

/// Who follows whom.
///
/// A follow is written as two mirrored rows in one batch, both created by the
/// follower: `users/{target}/followers/{me}` and `users/{me}/following/{target}`.
/// The document id of each row is the person that row is about, and its only
/// other field is `followedAt`, which is what the rules in `firestore.rules`
/// check. Mirroring keeps both directions a plain subcollection read instead of
/// a `where` query across a global collection.
class FollowRepository {
  FollowRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// One more than the largest list the rules allow. Reading this many rows is
  /// how the app knows a count went past the page it may read: Firestore cannot
  /// bound a `count()` aggregate with `request.query.limit`, because an
  /// aggregate carries no limit at all.
  static const countProbe = 201;

  /// The largest list the app shows, matching the rules' `list` cap.
  static const pageSize = 200;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _userId {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw StateError('Sign in to use MixSay follows');
    return userId;
  }

  CollectionReference<Map<String, dynamic>> _followersOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('followers');

  CollectionReference<Map<String, dynamic>> _followingOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('following');

  Future<FollowCount> followerCount(String userId) =>
      _count(_followersOf(userId));

  Future<FollowCount> followingCount(String userId) =>
      _count(_followingOf(userId));

  Future<FollowCount> _count(
    CollectionReference<Map<String, dynamic>> rows,
  ) async {
    final snapshot = await rows.limit(countProbe).get();
    final value = snapshot.docs.length;
    return FollowCount(value, capped: value >= countProbe);
  }

  Future<bool> isFollowing(String targetId) async {
    final userId = _userId;
    if (userId == targetId) return false;
    final row = await _followingOf(userId).doc(targetId).get();
    return row.exists;
  }

  /// The people who follow [userId], newest first.
  Future<List<FollowedUser>> followersOf(String userId) =>
      _people(_followersOf(userId));

  /// The people [userId] follows, newest first.
  Future<List<FollowedUser>> followingOf(String userId) =>
      _people(_followingOf(userId));

  Future<List<FollowedUser>> _people(
    CollectionReference<Map<String, dynamic>> rows,
  ) async {
    final snapshot = await rows
        .orderBy('followedAt', descending: true)
        .limit(pageSize)
        .get();
    return _profiles(snapshot.docs.map((document) => document.id).toList());
  }

  /// Reads every profile in parallel, newest first. A profile deleted between
  /// the two queries simply drops out of the list.
  Future<List<FollowedUser>> _profiles(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final profiles = await Future.wait(
      ids.map((id) async {
        final document = await _firestore
            .collection('publicProfiles')
            .doc(id)
            .get();
        final data = document.data();
        if (data == null) return null;
        return FollowedUser(
          id: id,
          username: data['username'] as String? ?? '',
          fullName: data['fullName'] as String? ?? '',
          avatarUrl: data['avatarUrl'] as String?,
        );
      }),
    );
    return profiles.nonNulls.toList(growable: false);
  }

  /// Adds or removes a follow and returns the state it ended on. Following
  /// yourself is refused here as well as by the rules.
  Future<bool> setFollowing(String targetId, {required bool following}) async {
    final userId = _userId;
    if (userId == targetId) {
      throw StateError('MixSay cannot follow yourself');
    }
    final batch = _firestore.batch();
    if (following) {
      final followedAt = FieldValue.serverTimestamp();
      batch.set(_followersOf(targetId).doc(userId), {
        'userId': userId,
        'followedAt': followedAt,
      });
      batch.set(_followingOf(userId).doc(targetId), {
        'userId': targetId,
        'followedAt': followedAt,
      });
    } else {
      batch.delete(_followersOf(targetId).doc(userId));
      batch.delete(_followingOf(userId).doc(targetId));
    }
    await batch.commit();
    return following;
  }
}
