import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/features/chat/chat_media.dart';

enum PendingQueueFailure { network, permanent }

PendingQueueFailure classifyPendingQueueFailure(Object error) {
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException) {
    return PendingQueueFailure.network;
  }
  if (error is FirebaseException &&
      const {
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
        'service-unavailable',
      }.contains(error.code)) {
    return PendingQueueFailure.network;
  }
  return PendingQueueFailure.permanent;
}

class PendingQueueTransaction {
  PendingQueueTransaction(this.entries, this._save);

  final List<Map<String, dynamic>> entries;
  final Future<void> Function(List<Map<String, dynamic>>) _save;

  Future<void> save() => _save(entries);
}

class PendingQueueService {
  PendingQueueService({this._preferences});

  static final instance = PendingQueueService();
  static const queueKey = 'pending_chat_messages';
  static const _corruptKeyPrefix = 'pending_chat_messages_corrupt_';
  static const _orphanAge = Duration(days: 7);

  SharedPreferences? _preferences;
  Future<void> _operationTail = Future<void>.value();

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<Map<String, dynamic>>> read() => _serialized(_readUnlocked);

  Future<void> enqueue(Map<String, dynamic> entry) => _serialized(() async {
    final entries = await _readUnlocked();
    final clientId = entry['client_id'];
    final senderId = entry['sender_id'];
    entries.removeWhere(
      (item) => item['client_id'] == clientId && item['sender_id'] == senderId,
    );
    entries.add({...entry, 'state': entry['state'] ?? 'queued'});
    await _writeUnlocked(entries);
  });

  Future<T> runExclusive<T>(
    Future<T> Function(PendingQueueTransaction transaction) operation,
  ) => _serialized(() async {
    final transaction = PendingQueueTransaction(
      await _readUnlocked(),
      _writeUnlocked,
    );
    return operation(transaction);
  });

  Future<void> setStateFor({
    required String clientId,
    required String senderId,
    required String state,
  }) => runExclusive((transaction) async {
    for (final entry in transaction.entries) {
      if (entry['client_id'] == clientId && entry['sender_id'] == senderId) {
        entry['state'] = state;
        entry.remove('next_attempt_at');
      }
    }
    await transaction.save();
  });

  Future<void> delete({required String clientId, required String senderId}) =>
      runExclusive((transaction) async {
        final removed = transaction.entries
            .where(
              (entry) =>
                  entry['client_id'] == clientId &&
                  entry['sender_id'] == senderId,
            )
            .toList();
        transaction.entries.removeWhere(
          (entry) =>
              entry['client_id'] == clientId && entry['sender_id'] == senderId,
        );
        await transaction.save();
        for (final entry in removed) {
          for (final path in ChatAttachmentDraft.queuedFilePaths(entry)) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
        }
      });

  /// Drops files in the pending folder that no queued message points at any
  /// more, once they are old enough that no send can still be waiting for the
  /// network. A queued GIF owns no file, so only real staged uploads count, and
  /// a clip owns two files: itself and the poster staged beside it.
  Future<void> cleanupOrphanedFiles() => runExclusive((transaction) async {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}/pending-chat',
    );
    if (!await directory.exists()) return;
    final referencedPaths = transaction.entries
        .expand(ChatAttachmentDraft.queuedFilePaths)
        .toSet();
    final cutoff = DateTime.now().subtract(_orphanAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || referencedPaths.contains(entity.path)) {
        continue;
      }
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (error, stackTrace) {
        _logFailure('remove an orphaned pending attachment', error, stackTrace);
      }
    }
  });

  Future<List<Map<String, dynamic>>> _readUnlocked() async {
    final preferences = await _prefs;
    final encoded = preferences.getString(queueKey);
    if (encoded == null) return [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        throw const FormatException('Queue root is not a list');
      }
      return decoded.map<Map<String, dynamic>>((item) {
        if (item is! Map) {
          throw const FormatException('Queue entry is not an object');
        }
        final entry = item.cast<String, dynamic>();
        if (entry['client_id'] is! String ||
            entry['conversation_id'] is! String ||
            entry['sender_id'] is! String ||
            entry['created_at'] is! String ||
            (entry['content'] != null && entry['content'] is! String) ||
            !ChatAttachmentDraft.queueFieldsAreValid(entry)) {
          throw const FormatException('Queue entry has invalid fields');
        }
        final state = entry['state'] ?? 'queued';
        if (!const {'queued', 'sending', 'failed'}.contains(state)) {
          throw const FormatException('Queue entry has an invalid state');
        }
        return {...entry, 'state': state};
      }).toList();
    } on FormatException catch (error, stackTrace) {
      final backupKey =
          '$_corruptKeyPrefix${DateTime.now().microsecondsSinceEpoch}';
      await preferences.setString(backupKey, encoded);
      await preferences.setString(queueKey, '[]');
      _logFailure(
        'recover a corrupted pending message queue',
        error,
        stackTrace,
      );
      return [];
    } catch (error, stackTrace) {
      final backupKey =
          '$_corruptKeyPrefix${DateTime.now().microsecondsSinceEpoch}';
      await preferences.setString(backupKey, encoded);
      await preferences.setString(queueKey, '[]');
      _logFailure(
        'recover an invalid pending message queue',
        error,
        stackTrace,
      );
      return [];
    }
  }

  Future<void> _writeUnlocked(List<Map<String, dynamic>> entries) async {
    final preferences = await _prefs;
    await preferences.setString(queueKey, jsonEncode(entries));
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint('Unable to $operation: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
