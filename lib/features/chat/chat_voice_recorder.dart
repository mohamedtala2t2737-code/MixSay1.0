import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'package:social_chat/features/chat/chat_media.dart';

/// The microphone, as far as the chat screen cares.
///
/// The plugin needs a device, a granted permission and a real encoder, so the
/// screen talks to this instead and a test hands [ChatVoiceRecorder] a fake.
abstract class ChatVoiceSource {
  Future<bool> hasPermission();

  /// Begins writing to [path].
  Future<void> start(String path);

  /// Ends the take and reports where it landed, or null when the platform has
  /// nothing to hand back.
  Future<String?> stop();

  Future<void> dispose();
}

/// The [ChatVoiceSource] that really records.
class ChatPluginVoiceSource implements ChatVoiceSource {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    // One channel at 64 kbit is what a note needs to stay intelligible, and
    // it is what keeps a ten-minute take under the 5 MB Storage ceiling.
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// One take at the microphone: whether it is running, how long it has run, and
/// the file it wrote.
///
/// The clock is a [Stopwatch] rather than the plugin's own position, because
/// `record` 7 reports none. It is monotonic, so a changed system time cannot
/// make a note longer than it was, and [isAtLimit] fires on the same tick the
/// composer paints.
class ChatVoiceRecorder {
  ChatVoiceRecorder({
    required this.source,
    Stopwatch? watch,
    this.maxDurationMs = chatMediaMaxDurationMs,
  }) : _watch = watch ?? Stopwatch();

  final ChatVoiceSource source;

  /// The length after which the composer stops the take.
  final int maxDurationMs;
  final Stopwatch _watch;

  String? _path;

  /// Whether a take is in progress, pause included.
  bool get isRecording => _path != null;

  /// Where the running take is being written, or null before it starts.
  String? get path => _path;

  Duration get elapsed => _watch.elapsed;

  int get elapsedMs => _watch.elapsedMilliseconds;

  /// Whether the take has reached the length `firestore.rules` still accepts.
  /// Past it the write would be refused, so the composer stops recording.
  bool get isAtLimit => _watch.elapsedMilliseconds >= maxDurationMs;

  /// Starts a take inside [directory], or returns null when the microphone is
  /// not allowed. The caller never sees a permission prompt of its own.
  Future<String?> start(String directory) async {
    if (_path != null) return _path;
    if (!await source.hasPermission()) return null;
    final path =
        '$directory/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await source.start(path);
    _path = path;
    _watch
      ..reset()
      ..start();
    return path;
  }

  /// Ends the take and keeps the file for sending. Null when nothing was
  /// running.
  Future<String?> stop() async {
    final path = _path;
    if (path == null) return null;
    _path = null;
    _watch.stop();
    return await source.stop() ?? path;
  }

  /// Ends the take and throws it away, which is what the sender asked for by
  /// pressing cancel.
  Future<void> cancel() async {
    final path = _path;
    if (path == null) return;
    _path = null;
    _watch.stop();
    final written = await source.stop();
    await _discard(written ?? path);
  }

  Future<void> dispose() async {
    await cancel();
    await source.dispose();
  }

  Future<void> _discard(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      // A take the app cannot delete is a file in the temporary folder, not a
      // lost message: the send has already been abandoned at this point.
      debugPrint('Unable to discard the recording: $error');
    }
  }
}
