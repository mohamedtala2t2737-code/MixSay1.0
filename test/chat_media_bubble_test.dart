import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_message_bubble.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_repository.dart';

const _me = 'me';
const _other = 'you';

ChatMessage _message({
  required ChatMessageType type,
  String content = '',
  String senderId = _me,
  String? mediaPath,
  String? thumbUrl,
  String? fileName,
  int? fileSize,
  int? durationMs,
  bool deletedForEveryone = false,
}) => ChatMessage(
  id: 'm1',
  conversationId: 'c1',
  senderId: senderId,
  content: content,
  status: 'sent',
  type: type,
  mediaPath: mediaPath,
  thumbUrl: thumbUrl,
  fileName: fileName,
  fileSize: fileSize,
  durationMs: durationMs,
  deletedForEveryone: deletedForEveryone,
  createdAt: DateTime(2026, 10, 15, 9, 30),
);

Widget _harness(
  ChatMessage message, {
  bool isOutgoing = true,
  Future<String>? imageUrl,
  Future<String>? thumbnailUrl,
  ChatVoicePlayback? voicePlayback,
  double? fileProgress,
  VoidCallback? onVideoTap,
  VoidCallback? onVoiceTap,
  VoidCallback? onFileTap,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppStrings.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppStrings.supportedLocales,
  home: Scaffold(
    body: ChatMessageBubble(
      message: message,
      isOutgoing: isOutgoing,
      currentUserId: _me,
      otherDisplayName: 'Salma',
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      voicePlayback: voicePlayback,
      fileProgress: fileProgress,
      onVideoTap: onVideoTap,
      onVoiceTap: onVoiceTap,
      onFileTap: onFileTap,
    ),
  ),
);

/// Localizations load asynchronously, and a resolved url needs one more frame
/// before the image widget is even built.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('video', () {
    testWidgets('shows the poster with its length and opens on tap', (
      tester,
    ) async {
      var opened = 0;
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.video,
            mediaPath: 'chats/c1/me/m.mp4',
            durationMs: 42000,
          ),
          thumbnailUrl: Future.value('https://example.test/m_thumb.jpg'),
          onVideoTap: () => opened++,
        ),
      );

      expect(find.text('0:42'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      expect(opened, 1);
    });

    testWidgets('a clip still uploading shows its length without a poster', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.video,
            durationMs: 5000,
            senderId: _other,
          ),
        ),
      );

      expect(find.text('0:05'), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a clip the sender deleted offers no way to open it', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.video,
            mediaPath: 'chats/c1/me/m.mp4',
            durationMs: 5000,
            deletedForEveryone: true,
          ),
          thumbnailUrl: Future.value('https://example.test/m_thumb.jpg'),
        ),
      );

      expect(find.byIcon(Icons.play_circle_fill), findsNothing);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });

  group('voice', () {
    testWidgets('shows how long the note is and starts on tap', (tester) async {
      var taps = 0;
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.voice,
            mediaPath: 'chats/c1/me/v.m4a',
            durationMs: 7000,
          ),
          onVoiceTap: () => taps++,
        ),
      );

      expect(find.text('0:07'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      expect(taps, 1);
    });

    testWidgets('the note being played shows pause and how far it got', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.voice,
            mediaPath: 'chats/c1/you/v.m4a',
            durationMs: 7000,
            senderId: _other,
          ),
          isOutgoing: false,
          voicePlayback: const ChatVoicePlayback(
            isPlaying: true,
            progress: 0.5,
            durationMs: 8000,
          ),
        ),
      );

      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      // The player's own length wins over the label the sender recorded.
      expect(find.text('0:08'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.5);
    });

    testWidgets('a note whose url is still resolving says so', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.voice,
            mediaPath: 'chats/c1/you/v.m4a',
            durationMs: 3000,
            senderId: _other,
          ),
          isOutgoing: false,
          voicePlayback: const ChatVoicePlayback(isLoading: true),
        ),
      );

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.text('0:03'), findsOneWidget);
    });
  });

  group('document', () {
    testWidgets('shows a readable name and the size it arrived with', (
      tester,
    ) async {
      var taps = 0;
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.file,
            mediaPath: 'chats/c1/you/report.pdf',
            fileName: '../../downloads/My Report (1).pdf',
            fileSize: 2 * 1024 * 1024,
            senderId: _other,
          ),
          isOutgoing: false,
          onFileTap: () => taps++,
        ),
      );

      expect(find.text('My Report (1).pdf'), findsOneWidget);
      expect(find.text('2 MB'), findsOneWidget);
      await tester.tap(find.text('My Report (1).pdf'));
      expect(taps, 1);
    });

    testWidgets('a document from a nameless sender still has a label', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.file,
            mediaPath: 'chats/c1/me/x.bin',
            fileName: '...',
          ),
        ),
      );

      expect(find.text('attachment'), findsOneWidget);
    });

    testWidgets('the bar fills while the file comes down', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.file,
            mediaPath: 'chats/c1/you/notes.txt',
            fileName: 'notes.txt',
            fileSize: 900,
            senderId: _other,
          ),
          isOutgoing: false,
          fileProgress: 0.25,
        ),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
    });
  });

  group('gif', () {
    testWidgets('is marked as moving', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.gif,
            mediaPath: 'https://tenor.example/cat.gif',
          ),
          imageUrl: Future.value('https://tenor.example/cat.gif'),
        ),
      );

      expect(find.text('GIF'), findsOneWidget);
    });
  });

  group('sticker shape', () {
    testWidgets('an uploaded sticker is the picture alone', (tester) async {
      await _show(
        tester,
        _harness(
          _message(
            type: ChatMessageType.sticker,
            mediaPath: 'chats/c1/me/stick.png',
          ),
          imageUrl: Future.value('https://example.test/stick.png'),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });
}
