import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:social_chat/core/utils/age_group.dart';

/// Keeps `publicProfiles/{uid}.ageGroup` equal to what the private birth date
/// says it should be.
///
/// The field is not a preference: the rules recompute it from the immutable
/// `users/{uid}.birthDate` and refuse any other value, so a profile written
/// before the field existed, and a teen whose eighteenth birthday has passed,
/// are both corrected by one write to the owner's own document.
class AgeGroupService {
  AgeGroupService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _noBirthDate = "MixSay cannot find your birth date.";
  static const _noProfile = 'Complete your profile before searching.';

  final FirebaseFirestore _firestore;

  /// Groups already settled this session. A search runs on every pause in
  /// typing, and this answer only changes when somebody has a birthday.
  final _settled = <String, AgeGroup>{};

  /// The signed-in user's group, written to their own profile when the profile
  /// is missing the field or still holds the group they have grown out of.
  Future<AgeGroup> resolve(String userId) async {
    final cached = _settled[userId];
    if (cached != null) return cached;

    final user = await _firestore.collection('users').doc(userId).get();
    final birthDate = user.data()?['birthDate'];
    if (birthDate is! Timestamp) {
      throw StateError(_noBirthDate);
    }

    final group = AgeGroup.of(
      birthDate: birthDate.toDate(),
      now: DateTime.now().toUtc(),
    );

    final profile = await _firestore
        .collection('publicProfiles')
        .doc(userId)
        .get();
    if (!profile.exists) throw StateError(_noProfile);
    if (AgeGroup.fromWire(profile.data()?['ageGroup']) != group) {
      await _firestore.collection('publicProfiles').doc(userId).update({
        'ageGroup': group.wire,
      });
    }

    _settled[userId] = group;
    return group;
  }
}
