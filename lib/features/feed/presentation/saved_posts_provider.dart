import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved posts live on the device: Firestore has no `saves` collection, so a
/// server-side bookmark would need new rules and a new subcollection.
class SavedPostsController extends Notifier<Set<String>> {
  static const _prefsKey = 'saved_post_ids';

  @override
  Set<String> build() => const {};

  Future<void> restore() async {
    final ids = await _read();
    if (ids.isNotEmpty) state = ids;
  }

  Future<void> toggle(String postId) async {
    final next = Set<String>.from(state);
    if (!next.remove(postId)) next.add(postId);
    state = next;
    await _write(next);
  }

  Future<Set<String>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsKey) ?? const []).toSet();
    } catch (error) {
      debugPrint('Unable to read saved posts: $error');
      return const {};
    }
  }

  Future<void> _write(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, ids.toList(growable: false));
    } catch (error) {
      debugPrint('Unable to save posts: $error');
    }
  }
}

final savedPostsProvider = NotifierProvider<SavedPostsController, Set<String>>(
  SavedPostsController.new,
);
