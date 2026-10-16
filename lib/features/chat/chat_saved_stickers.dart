import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:social_chat/features/chat/chat_stickers.dart';

/// A sticker the user asked to keep, in the shape Firestore stores it.
///
/// A save is a bookmark, not a copy. The row holds the pack id and the sticker
/// name — the same two halves the message bubble carries in `stickerId` — and
/// the picture still comes out of the app's own assets. That is what lets the
/// free plan hold a sticker shelf: no upload, no Storage object, and no field
/// `firestore.rules` has never heard of.
///
/// A sticker the user uploaded themselves cannot be bookmarked this way, so the
/// UI keeps that option hidden while `ChatFeatures.userUploadedStickers` is off.
class SavedSticker {
  const SavedSticker({required this.packId, required this.sticker});

  /// The pack folder, as it appears in [chatStickerPacks].
  final String packId;

  /// The file name inside the pack, without the `.png` extension.
  final String sticker;

  /// The document id: both halves joined with `_`, which is why neither half may
  /// hold one. Two stickers can therefore never share a row, and one sticker
  /// can never have two rows however often its star is tapped.
  String get rowId => '${packId}_$sticker';

  /// The id a `sticker` message carries for this picture.
  String get stickerId => '$packId/$sticker';

  /// The asset to paint, or null when this build no longer ships the pack.
  String? get asset => chatStickerAssetOf(stickerId);

  /// The bookmark for a message's `stickerId`, or null when this build has no
  /// such picture.
  ///
  /// [chatStickerAssetOf] is the same whitelist the bubble paints from, so an
  /// id that arrives from another device — or one typed into a made-up message
  /// — can never be turned into a row. The rules check the shape again; this
  /// only keeps the app from attempting a write it knows will be refused.
  static SavedSticker? fromStickerId(String? stickerId) {
    final id = stickerId;
    if (id == null) return null;
    final slash = id.indexOf('/');
    if (slash <= 0 || slash == id.length - 1) return null;
    final packId = id.substring(0, slash);
    final sticker = id.substring(slash + 1);
    // No picture this build ships, nothing to bookmark: an id invented by
    // another device can never become a row.
    if (chatStickerAssetOf(id) == null) return null;
    // The row id joins the halves with `_`, so a half holding one would make
    // two different stickers share a row and one save silently replace the
    // other. `firestore.rules` refuses the same shape.
    if (packId.contains('_') || sticker.contains('_')) return null;
    return SavedSticker(packId: packId, sticker: sticker);
  }

  /// The bookmark a stored row describes, or null when the row is not one this
  /// app can draw.
  ///
  /// A row written by a newer build may name a pack this one dropped. Showing it
  /// would put a broken tile on the shelf, so it is left out instead.
  static SavedSticker? fromRow(Map<String, dynamic>? data) {
    final packId = data?['packId'];
    final sticker = data?['sticker'];
    if (packId is! String || sticker is! String) return null;
    return fromStickerId('$packId/$sticker');
  }

  /// The three fields `firestore.rules` accepts for one row.
  Map<String, Object?> toRow() => {
    'packId': packId,
    'sticker': sticker,
    'savedAt': FieldValue.serverTimestamp(),
  };

  @override
  bool operator ==(Object other) =>
      other is SavedSticker &&
      other.packId == packId &&
      other.sticker == sticker;

  @override
  int get hashCode => Object.hash(packId, sticker);

  @override
  String toString() => 'SavedSticker($stickerId)';
}

/// Why a save could not happen, in words the screen can show.
enum SavedStickerOutcome {
  /// The row is on the shelf — including when it already was.
  saved,

  /// The shelf holds [SavedStickerRepository.capacity] bookmarks already.
  full,

  /// The id names no sticker this build ships, so there is nothing to save.
  unknownSticker,
}

/// The user's sticker shelf: `users/{uid}/savedStickers`.
///
/// Everything here is owner-only and reference-only, which is exactly what
/// `firestore.rules` allows: one row per sticker, three fields, and no list read
/// bigger than [capacity].
class SavedStickerRepository {
  SavedStickerRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// How many bookmarks one account may hold — and the largest list the rules
  /// allow anybody to read. They are the same number on purpose: reading this
  /// many rows is the only way to count the shelf, because Firestore rules
  /// cannot count a collection and a `count()` aggregate carries no limit, so
  /// `request.query.limit` cannot bound it.
  static const capacity = 200;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _shelf(String userId) =>
      _firestore.collection('users').doc(userId).collection('savedStickers');

  /// The shelf, newest save first, capped at [capacity] rows — the ceiling the
  /// rules enforce on the read too.
  Stream<List<SavedSticker>> watchSaved({required String userId}) =>
      _shelf(userId)
          .orderBy('savedAt', descending: true)
          .limit(capacity)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((document) => SavedSticker.fromRow(document.data()))
                .nonNulls
                .toList(growable: false),
          );

  /// Bookmark the sticker a message carries.
  ///
  /// Returns [SavedStickerOutcome.saved] when the row is there afterwards, even
  /// if an earlier tap had already put it there — a second tap on the star is a
  /// no-op, not a failure the user should be told about.
  Future<SavedStickerOutcome> save(
    String? stickerId, {
    required String userId,
  }) async {
    final sticker = SavedSticker.fromStickerId(stickerId);
    if (sticker == null) return SavedStickerOutcome.unknownSticker;
    final row = _shelf(userId).doc(sticker.rowId);
    // One read settles the duplicate case, which is the common one.
    if ((await row.get()).exists) return SavedStickerOutcome.saved;
    final shelf = await _shelf(userId).limit(capacity).get();
    if (shelf.size >= capacity) return SavedStickerOutcome.full;
    await row.set(sticker.toRow());
    return SavedStickerOutcome.saved;
  }

  /// Take a bookmark off the shelf. Removing what is not there is a no-op, since
  /// the caller is looking at a row it cannot re-check.
  Future<void> remove(String? stickerId, {required String userId}) async {
    final sticker = SavedSticker.fromStickerId(stickerId);
    if (sticker == null) return;
    await _shelf(userId).doc(sticker.rowId).delete();
  }
}
