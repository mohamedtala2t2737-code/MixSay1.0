import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/features/auth/presentation/auth_providers.dart';

/// Which authors this device has already opened stories for, which is what turns
/// a rail ring from brand-coloured to grey.
///
/// It is deliberately local: the `stories/{id}/viewers` subcollection records a
/// view for the author to read, not for the viewer, so there is nothing the rail
/// could query to find out whether *I* watched *you*. The key carries the account
/// id so two users on the same phone do not share marks.
class SeenStoriesController extends Notifier<Set<String>> {
  static String keyFor(String userId) => 'seen_story_groups_$userId';

  @override
  Set<String> build() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const {};
    // Not awaited: another author's ring only appears once the story query has
    // come back, which is always after this local read. Awaiting would put the
    // provider in a loading state and grey every ring for a frame.
    _restore(userId);
    return const {};
  }

  Future<void> markSeen(String authorId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || state.contains(authorId)) return;
    state = <String>{...state, authorId};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(keyFor(userId), state.toList(growable: false));
    } catch (error) {
      debugPrint('Unable to store seen stories: $error');
    }
  }

  Future<void> _restore(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(keyFor(userId));
      if (stored == null || stored.isEmpty) return;
      // Anything marked while the read was in flight is newer than it, so the
      // stored list is added to the current state instead of replacing it.
      state = <String>{...state, ...stored};
    } catch (error) {
      debugPrint('Unable to read seen stories: $error');
    }
  }
}

final seenStoriesProvider =
    NotifierProvider<SeenStoriesController, Set<String>>(
      SeenStoriesController.new,
    );
