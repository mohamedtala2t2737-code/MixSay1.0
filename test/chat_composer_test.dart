import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/config/chat_secrets.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/features/chat/chat_composer.dart';
import 'package:social_chat/features/chat/chat_emoji_picker.dart';
import 'package:social_chat/features/chat/chat_message_type.dart';
import 'package:social_chat/features/chat/chat_stickers.dart';
import 'package:social_chat/features/chat/chat_tray.dart';

/// What a tap on the screen actually did, so a test can tell a control that is
/// waiting for a send to finish from one that was never drawn.
class _Taps {
  int tray = 0;
  int attach = 0;
  int camera = 0;
  int mic = 0;
  int send = 0;
}

final _screenSource = File('lib/features/chat/chat_screen.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

final _traySource = File('lib/features/chat/chat_tray.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

Future<void> _pumpComposer(
  WidgetTester tester,
  TextEditingController controller, {
  bool trayAvailable = true,
  bool attachAvailable = true,
  bool cameraAvailable = true,
  bool micAvailable = true,
  bool trayOpen = false,
  bool busy = false,
  _Taps? taps,
}) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: ChatComposer(
          controller: controller,
          focusNode: focusNode,
          trayAvailable: trayAvailable,
          attachAvailable: attachAvailable,
          cameraAvailable: cameraAvailable,
          micAvailable: micAvailable,
          trayOpen: trayOpen,
          busy: busy,
          onTrayTap: () => taps?.tray++,
          onAttachTap: () => taps?.attach++,
          onCameraTap: () => taps?.camera++,
          onMicTap: () => taps?.mic++,
          onSend: () => taps?.send++,
          onTextChanged: (_) {},
        ),
      ),
    ),
  );
  // The strings arrive asynchronously, so the first frame has no tooltips in it.
  await tester.pump();
}

Future<void> _pumpTray(WidgetTester tester, ChatTray tray) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: Scaffold(
        body: Column(children: [Expanded(child: tray)]),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The colour the round button asks for. Read off the style rather than off a
/// painted layer, so a theme change cannot make the test agree with the app by
/// accident.
Color? _askedColor(WidgetTester tester, IconData icon) => tester
    .widget<IconButton>(
      find
          .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
          .first,
    )
    .style
    ?.backgroundColor
    ?.resolve(const <WidgetState>{});

bool _acceptsTaps(WidgetTester tester, IconData icon) =>
    tester
        .widget<IconButton>(
          find
              .ancestor(
                of: find.byIcon(icon),
                matching: find.byType(IconButton),
              )
              .first,
        )
        .onPressed !=
    null;

void main() {
  group('the round button', () {
    testWidgets('it sends what the field holds', (tester) async {
      final controller = TextEditingController(text: 'ahlan');
      addTearDown(controller.dispose);
      final taps = _Taps();
      await _pumpComposer(tester, controller, taps: taps);

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(taps.send, 1);
      expect(taps.mic, 0);
    });

    testWidgets('an empty field turns it into a mic', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final taps = _Taps();
      await _pumpComposer(tester, controller, taps: taps);

      expect(find.byIcon(Icons.mic_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_outlined));
      expect(taps.mic, 1);
      expect(taps.send, 0);
    });

    testWidgets('an empty field with no voice to record shows neither', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller, micAvailable: false);

      expect(find.byIcon(Icons.mic_outlined), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      // The field is untouched, so a message can still be written.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('writing turns the mic into send', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller);

      await tester.enterText(find.byType(TextField), 'salam');
      await tester.pump();

      expect(find.byIcon(Icons.mic_outlined), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('spaces are not a message', (tester) async {
      final controller = TextEditingController(text: '   ');
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller);

      expect(find.byIcon(Icons.send_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_outlined), findsOneWidget);
    });

    testWidgets('it is the chat green, not the brand purple', (tester) async {
      final controller = TextEditingController(text: 'ahlan');
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller);

      expect(
        _askedColor(tester, Icons.send_rounded),
        AppColors.chatActionGreen,
      );
    });

    testWidgets('while a send is running it spins and answers nothing', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ahlan');
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller, busy: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_acceptsTaps(tester, Icons.attach_file), isFalse);
      expect(_acceptsTaps(tester, Icons.photo_camera_outlined), isFalse);
    });

    testWidgets('a running recording takes the field away entirely', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: ChatComposer(
              controller: controller,
              focusNode: focusNode,
              trayAvailable: true,
              attachAvailable: true,
              cameraAvailable: true,
              micAvailable: true,
              trayOpen: false,
              busy: false,
              inFlight: const Text('0:07'),
              onTrayTap: () {},
              onAttachTap: () {},
              onCameraTap: () {},
              onMicTap: () {},
              onSend: () {},
              onTextChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('0:07'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });
  });

  group('the icons around the field', () {
    testWidgets('a control only appears when it can do something', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ahlan');
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);

      await _pumpComposer(
        tester,
        controller,
        trayAvailable: false,
        attachAvailable: false,
        cameraAvailable: false,
      );
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    });

    testWidgets('the panel button becomes the keyboard button while open', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final taps = _Taps();
      await _pumpComposer(tester, controller, trayOpen: true, taps: taps);

      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      expect(taps.tray, 1);
    });

    testWidgets('the camera and the panel say what they are for', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpComposer(tester, controller, micAvailable: false);

      expect(find.byTooltip('Camera'), findsOneWidget);
      expect(find.byTooltip('Emoji'), findsOneWidget);
    });

    test('the screen hands the composer nothing a flag has switched off', () {
      expect(
        _screenSource,
        contains('micAvailable: !ChatMessageType.voice.isGated'),
      );
      expect(
        _screenSource,
        contains('cameraAvailable: !ChatMessageType.image.isGated'),
      );
      expect(
        _screenSource,
        contains('trayAvailable: ChatTray.availableTabs().isNotEmpty'),
      );
      expect(_screenSource, contains('attachAvailable:'));
    });

    test('the camera icon is a camera', () {
      expect(_screenSource, contains('_sendCameraPhoto'));
      expect(_screenSource, contains('ImageSource.camera'));
    });
  });

  group('the panel', () {
    test('every tab it can list is one the flags allow', () {
      final tabs = ChatTray.availableTabs();
      expect(tabs.contains(ChatTrayTab.emoji), ChatFeatures.emojiPicker);
      expect(
        tabs.contains(ChatTrayTab.stickers),
        !ChatMessageType.sticker.isGated,
      );
      expect(
        tabs.contains(ChatTrayTab.gif),
        ChatFeatures.gifSearch && ChatSecrets.hasTenorKey,
        reason: 'a search that cannot reach Tenor is not offered',
      );
    });

    test('a GIF tab needs both the flag and a key', () {
      expect(
        _traySource,
        contains(
          'if (ChatFeatures.gifSearch && ChatSecrets.hasTenorKey) ChatTrayTab.gif',
        ),
      );
    });

    test('there is no saved tab until saving exists', () {
      expect(ChatTrayTab.values.map((tab) => tab.name).toList(), [
        'emoji',
        'stickers',
        'gif',
      ]);
    });

    testWidgets('with no tabs it draws nothing', (tester) async {
      await _pumpTray(
        tester,
        ChatTray(
          initial: ChatTrayTab.emoji,
          tabs: const [],
          onEmoji: (_) {},
          onSticker: (_) {},
        ),
      );
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('it opens on the tab the composer button chose', (
      tester,
    ) async {
      var picked = '';
      await _pumpTray(
        tester,
        ChatTray(
          initial: ChatTrayTab.stickers,
          tabs: const [ChatTrayTab.emoji, ChatTrayTab.stickers],
          onSticker: (id) => picked = id,
          onEmoji: (_) {},
        ),
      );

      // A sticker picture on screen is the proof this is the page that shows.
      expect(find.byType(Image), findsWidgets);
      await tester.tap(find.byType(Image).first);
      expect(picked, isNotEmpty);
    });

    testWidgets('moving to a tab opens its body and says so', (tester) async {
      final seen = <ChatTrayTab>[];
      await _pumpTray(
        tester,
        ChatTray(
          initial: ChatTrayTab.emoji,
          tabs: const [ChatTrayTab.emoji, ChatTrayTab.stickers],
          onEmoji: (_) {},
          onSticker: (_) {},
          onTabChanged: seen.add,
        ),
      );

      await tester.tap(find.text('Stickers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(seen, [ChatTrayTab.stickers]);
      expect(find.byType(ChatStickerPicker), findsOneWidget);
      expect(find.byType(ChatEmojiPicker), findsNothing);
    });

    testWidgets('an emoji tap hands the character over', (tester) async {
      final written = <String>[];
      await _pumpTray(
        tester,
        ChatTray(
          initial: ChatTrayTab.emoji,
          tabs: const [ChatTrayTab.emoji],
          onEmoji: written.add,
          onSticker: (_) {},
        ),
      );

      await tester.tap(find.text('😀'));
      expect(written, ['😀']);
    });
  });

  group('the panel and the keyboard', () {
    test('opening the panel takes the focus away from the field', () {
      expect(_screenSource, contains('_messageFocusNode.unfocus()'));
      expect(
        _screenSource,
        contains('_messageFocusNode.addListener(_onFieldFocusChanged)'),
      );
    });

    test('touching the field closes the panel', () {
      expect(
        _screenSource,
        contains('if (_messageFocusNode.hasFocus && _trayOpen && mounted)'),
      );
    });

    test('an emoji does not summon the keyboard while the panel is open', () {
      expect(
        _screenSource,
        contains('if (!_trayOpen) _messageFocusNode.requestFocus();'),
      );
    });

    test('the panel slides up under the composer, not over it', () {
      expect(_screenSource, contains('child: _trayOpen'));
      expect(_screenSource, contains('AnimatedSize('));
      expect(_screenSource, contains('ChatTray('));
    });
  });
}
