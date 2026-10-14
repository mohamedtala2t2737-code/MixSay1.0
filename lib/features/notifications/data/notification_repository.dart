import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.postId,
    this.conversationId,
  });

  final String id;
  final String recipientId;
  final String actorId;
  final String actorName;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final String? postId;
  final String? conversationId;

  factory AppNotification.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final timestamp = data['createdAt'];
    return AppNotification(
      id: document.id,
      recipientId: data['recipientId'] as String? ?? '',
      actorId: data['actorId'] as String? ?? '',
      actorName: data['actorName'] as String? ?? '',
      type: data['type'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      postId: data['postId'] as String?,
      conversationId: data['conversationId'] as String?,
    );
  }
}

class NotificationRepository {
  NotificationRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _userId {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw StateError('Sign in to view notifications');
    }
    return userId;
  }

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  Stream<List<AppNotification>> watchNotifications() => _notifications
      .where('recipientId', isEqualTo: _userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(AppNotification.fromFirestore)
            .toList(growable: false),
      );

  Future<void> markRead(String notificationId) async {
    await _notifications.doc(notificationId).update({'isRead': true});
  }

  Future<void> markAllRead(List<AppNotification> notifications) async {
    final unread = notifications.where((notification) => !notification.isRead);
    final documents = unread.toList(growable: false);
    for (var offset = 0; offset < documents.length; offset += 450) {
      final batch = _firestore.batch();
      for (final notification in documents.skip(offset).take(450)) {
        batch.update(_notifications.doc(notification.id), {'isRead': true});
      }
      await batch.commit();
    }
  }
}
