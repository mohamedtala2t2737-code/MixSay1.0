import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What a report points at. The rules accept exactly these two values.
enum ReportTarget {
  post('post'),
  story('story');

  const ReportTarget(this.value);

  final String value;
}

/// Why the content is being reported. `firestore.rules` lists the same six, so a
/// new reason needs a rules change before the app can send it.
enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  nudity('nudity'),
  violence('violence'),
  misinformation('misinformation'),
  other('other');

  const ReportReason(this.value);

  final String value;
}

/// Reports are write-only: the document is read in the Firebase console, never
/// by a client, so this class has no queries.
class ReportRepository {
  ReportRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// Matches the `extraNote.size() <= 300` rule.
  static const noteMaxLength = 300;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Whitespace goes away and a blank note is dropped entirely, which is the
  /// shape the optional `extraNote` rule expects.
  static String? normalizeNote(String? raw) {
    final note = raw?.trim();
    return note == null || note.isEmpty ? null : note;
  }

  /// The id is `reporter_target`, which makes a second report of the same thing
  /// an impossible write instead of another document.
  Future<void> submit({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? extraNote,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before reporting content');

    final note = normalizeNote(extraNote);
    final data = <String, dynamic>{
      'reporterId': uid,
      'targetType': target.value,
      'targetId': targetId,
      'reason': reason.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (note != null) data['extraNote'] = note;

    await _firestore.doc('reports/${uid}_$targetId').set(data);
  }
}
