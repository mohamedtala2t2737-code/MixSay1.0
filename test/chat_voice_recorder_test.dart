import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/features/chat/chat_voice_recorder.dart';

/// A microphone that only says what the test tells it to.
class _FakeVoiceSource implements ChatVoiceSource {
  _FakeVoiceSource({this.allowed = true, this.reports});

  /// Whether the system hands over the microphone.
  final bool allowed;

  /// What the platform reports as the finished file, in place of the path it
  /// was given. null is the honest answer of a platform with nothing to hand
  /// back.
  final String? reports;

  int starts = 0;
  int stops = 0;
  int disposes = 0;
  String? lastPath;

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<void> start(String path) async {
    starts++;
    lastPath = path;
    File(path).writeAsStringSync('bytes that stand in for audio');
  }

  @override
  Future<String?> stop() async {
    stops++;
    return reports ?? lastPath;
  }

  @override
  Future<void> dispose() async {
    disposes++;
  }
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mixsay_chat_voice');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  ChatVoiceRecorder take(_FakeVoiceSource source, {int? maxDurationMs}) =>
      ChatVoiceRecorder(source: source, maxDurationMs: maxDurationMs ?? 600000);

  group('a take', () {
    test('refuses to start when the microphone is not allowed', () async {
      final source = _FakeVoiceSource(allowed: false);
      final recorder = take(source);

      expect(await recorder.start(directory.path), isNull);
      expect(source.starts, 0, reason: 'no session was opened');
      expect(recorder.isRecording, isFalse);
      expect(recorder.path, isNull);
    });

    test('writes inside the folder it was given, as one file', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);

      final path = await recorder.start(directory.path);
      expect(path, isNotNull);
      expect(path, startsWith('${directory.path}/'));
      expect(path, endsWith('.m4a'));
      expect(recorder.isRecording, isTrue);
      expect(File(path!).existsSync(), isTrue);
    });

    test('a second press keeps the take that is already running', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);

      final first = await recorder.start(directory.path);
      final second = await recorder.start(directory.path);

      expect(second, first);
      expect(source.starts, 1, reason: 'one session per take');
    });

    test('stopping keeps the recording for sending', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);
      final path = await recorder.start(directory.path);

      expect(await recorder.stop(), path);
      expect(recorder.isRecording, isFalse);
      expect(source.stops, 1);
      expect(File(path!).existsSync(), isTrue);
    });

    test('the take lands where the platform says it landed', () async {
      // Android answers with its own path; the caller has to be told that one,
      // or the upload would point at a file that was never written.
      final elsewhere = '${directory.path}/from_the_platform.m4a';
      final source = _FakeVoiceSource(reports: elsewhere);
      final recorder = take(source);
      await recorder.start(directory.path);

      expect(await recorder.stop(), elsewhere);
    });

    test('nothing to stop answers with nothing', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);

      expect(await recorder.stop(), isNull);
      expect(source.stops, 0);
    });

    test('cancelling throws the recording away', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);
      final path = await recorder.start(directory.path);

      await recorder.cancel();

      expect(recorder.isRecording, isFalse);
      expect(source.stops, 1);
      expect(File(path!).existsSync(), isFalse);
    });

    test('a cancel with no take touches no microphone', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);

      await recorder.cancel();

      expect(source.stops, 0);
    });

    test('leaving the chat gives the microphone back', () async {
      final source = _FakeVoiceSource();
      final recorder = take(source);
      final path = await recorder.start(directory.path);

      await recorder.dispose();

      expect(source.stops, 1);
      expect(source.disposes, 1);
      expect(File(path!).existsSync(), isFalse);
    });
  });

  group('the clock', () {
    test('the ten-minute ceiling is what the rules still accept', () {
      // A note longer than this is refused by `firestore.rules`, so the
      // composer has to stop the recording rather than lose the send.
      final recorder = ChatVoiceRecorder(
        source: _FakeVoiceSource(),
        watch: Stopwatch()..start(),
        maxDurationMs: 0,
      );
      expect(recorder.isAtLimit, isTrue);
    });

    test('a fresh take is nowhere near the ceiling', () async {
      final recorder = take(_FakeVoiceSource());
      await recorder.start(directory.path);
      expect(recorder.isAtLimit, isFalse);
    });

    test('starting a take puts the clock back to zero', () async {
      final watch = Stopwatch()..start();
      final recorder = ChatVoiceRecorder(
        source: _FakeVoiceSource(),
        watch: watch,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await recorder.start(directory.path);

      expect(recorder.elapsedMs, lessThan(20));
    });
  });
}
