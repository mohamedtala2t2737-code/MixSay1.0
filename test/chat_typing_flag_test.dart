import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The chat screen cannot be pumped without Firebase, and the typing flag is
/// one document field on the other side of a Firestore write, so what a test
/// can hold this code to is the shape of the writes it makes: one throttled
/// write up, one write down, and that down-write also fires when the screen is
/// torn down.
///
/// Checked out sources carry CRLF on Windows, so the file is read as one line
/// ending.
final _screenSource = File('lib/features/chat/chat_screen.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

/// The body of [name], from its opening brace to the brace that closes it.
///
/// Assertions about a method have to be about that method: the file also
/// contains the same calls in other places, and a plain `contains` would pass
/// on the wrong one.
String _body(String name) {
  final start = _screenSource.indexOf('$name(');
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: '$name is gone from the screen',
  );
  final open = _screenSource.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < _screenSource.length; i++) {
    final char = _screenSource[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return _screenSource.substring(open, i + 1);
    }
  }
  fail('$name has no closing brace');
}

void main() {
  group('writing the flag', () {
    test('a keystroke waits instead of writing on every one', () {
      final body = _body('void _onTextChanged');
      // The previous claim is dropped before a new one is scheduled, so fast
      // typing costs one write per pause rather than one per letter.
      expect(body, contains('_typingDebounce?.cancel()'));
      expect(body, contains('Timer('));
      expect(body, contains('_claimTyping'));
      expect(
        body.contains('setTyping'),
        isFalse,
        reason: 'the field itself must not reach Firestore',
      );
    });

    test('the throttle is a pause, not a per-keystroke timer', () {
      final body = _body('void _onTextChanged');
      final delay = RegExp(r'Duration\(([^)]*)\)').firstMatch(body)?.group(1);
      expect(delay, contains('milliseconds'));
      expect(delay, contains('400'));
    });

    test('an emptied field is the end of typing, not a pause', () {
      final body = _body('void _onTextChanged');
      expect(body, contains('trim().isEmpty'));
      expect(body, contains('_stopClaimingTyping()'));
    });

    test('the flag is written by a timer that also lets it expire', () {
      final body = _body('Future<void> _claimTyping');
      expect(body, contains('setTyping(widget.conversationId, true)'));
      expect(body, contains('Timer(_typingLinger, _stopClaimingTyping)'));
    });

    test('the offline composer claims nothing', () {
      expect(
        _body('Future<void> _claimTyping'),
        startsWith('{\n    if (_offline) return;'),
      );
    });
  });

  group('clearing the flag', () {
    test('the clear is one write, fired and forgotten', () {
      final body = _body('void _releaseTyping');
      expect(body, contains('_claimingTyping'));
      expect(body, contains('setTyping(widget.conversationId, false)'));
      // A departing sender cannot wait for the network, and a failure here has
      // to be said out loud rather than thrown into the frame.
      expect(body, contains('unawaited('));
      expect(body, contains('catchError'));
    });

    test('leaving the chat clears the flag', () {
      final body = _body('void dispose');
      expect(body, contains('_releaseTyping()'));
      expect(
        body.contains('ref.read'),
        isFalse,
        reason:
            'reading a provider from dispose throws, so the clear would '
            'never reach Firestore',
      );
      expect(
        body.contains('ref.'),
        isFalse,
        reason: 'nothing in dispose may touch the widget bindings providers',
      );
    });

    test('the screen keeps the writer it claimed with', () {
      final body = _body('Future<void> _claimTyping');
      expect(
        body,
        contains('final repository = ref.read(chatRepositoryProvider);'),
      );
      expect(body, contains('_typingWriter = repository'));
      expect(body, contains('repository.setTyping('));
      expect(
        body.contains('ref.read(chatRepositoryProvider).setTyping'),
        isFalse,
        reason:
            'a provider read at the moment of clearing is what dispose cannot '
            'do, so the repository is captured instead',
      );
    });

    test('sending a message clears the flag too', () {
      expect(
        _body('Future<void> _sendMessage'),
        contains('_stopClaimingTyping()'),
      );
    });

    test('stopping and releasing are the same clear', () {
      final body = _body('void _stopClaimingTyping');
      expect(body, contains('_typingDebounce?.cancel()'));
      expect(body, contains('_releaseTyping()'));
    });
  });

  group('showing the other side', () {
    test('the app bar asks the repository for the other flag', () {
      expect(_screenSource, contains('watchOtherTyping('));
      expect(_screenSource, contains('_otherTyping = isTyping'));
    });
  });
}
