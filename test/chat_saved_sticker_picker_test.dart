import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/chat/chat_saved_sticker_picker.dart';
import 'package:social_chat/features/chat/chat_saved_stickers.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Records the removals the panel asks for. Anything else on a repository is a
/// bug in a test, so it throws instead of quietly returning null.
class _FakeSavedStickerRepository implements SavedStickerRepository {
  final List<String> removed = [];
  Object? failRemove;

  @override
  Future<void> remove(String? stickerId, {required String userId}) async {
    final error = failRemove;
    if (error != null) throw error;
    removed.add(stickerId!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'SavedStickerRepository.${invocation.memberName} is not faked',
  );
}

Widget _harness(
  Stream<List<SavedSticker>> shelf, {
  Locale locale = const Locale('en'),
  ValueChanged<String>? onSelected,
  _FakeSavedStickerRepository? repository,
}) => ProviderScope(
  overrides: [
    currentUserIdProvider.overrideWithValue('alice'),
    savedStickerRepositoryProvider.overrideWithValue(
      repository ?? _FakeSavedStickerRepository(),
    ),
    savedStickersProvider.overrideWith((ref) => shelf),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        height: 228,
        child: ChatSavedStickerPicker(onSelected: onSelected ?? (_) {}),
      ),
    ),
  ),
);

SavedSticker _sticker(String name) =>
    SavedSticker.fromStickerId('mixsay-friends/$name')!;

/// The tiles are the only InkWells in this tree, and a long press is what
/// removes one, so this picks a tile out by its place on the shelf.
Finder _tile(WidgetTester tester, int index) {
  final tiles = tester.widgetList<InkWell>(
    find.byWidgetPredicate(
      (widget) => widget is InkWell && widget.onLongPress != null,
    ),
  );
  return find.byWidget(tiles.toList()[index]);
}

Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  // Localizations load asynchronously and the shelf arrives on a stream, so the
  // first frames are still the spinner.
  await tester.pumpAndSettle();
}

void main() {
  group('the shelf', () {
    testWidgets('says how a bookmark is made while it is empty', (
      tester,
    ) async {
      await _show(tester, _harness(Stream.value(const [])));

      expect(find.text('No saved stickers yet'), findsOneWidget);
      // The gesture that makes one has to be written down, not assumed.
      expect(
        find.text(
          'Press and hold any sticker in a chat, then choose Save sticker.',
        ),
        findsOneWidget,
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('paints one picture per bookmark', (tester) async {
      await _show(
        tester,
        _harness(Stream.value([_sticker('cat'), _sticker('sun')])),
      );

      for (final name in ['cat', 'sun']) {
        final painted = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/stickers/mixsay-friends/$name.png',
        );
        expect(painted, findsOneWidget, reason: '$name is on the shelf');
      }
      // A control nobody hinted at is a control nobody finds.
      expect(
        find.text('Press and hold a sticker to take it off the shelf'),
        findsOneWidget,
      );
    });

    testWidgets('a tap sends the sticker, not a copy of it', (tester) async {
      final sent = <String>[];
      await _show(
        tester,
        _harness(
          Stream.value([_sticker('cat'), _sticker('sun')]),
          onSelected: sent.add,
        ),
      );

      await tester.tap(_tile(tester, 0));
      await tester.pump();

      expect(sent, ['mixsay-friends/cat']);
    });

    testWidgets('a long press takes the bookmark off, not the picture', (
      tester,
    ) async {
      final repository = _FakeSavedStickerRepository();
      await _show(
        tester,
        _harness(
          Stream.value([_sticker('cat'), _sticker('sun')]),
          repository: repository,
        ),
      );

      await tester.longPress(_tile(tester, 1));
      await tester.pumpAndSettle();

      expect(repository.removed, ['mixsay-friends/sun']);
      expect(find.text('Removed from Saved'), findsOneWidget);
    });

    testWidgets('a removal that failed says so instead of lying', (
      tester,
    ) async {
      final repository = _FakeSavedStickerRepository()
        ..failRemove = Exception('offline');
      await _show(
        tester,
        _harness(Stream.value([_sticker('cat')]), repository: repository),
      );

      await tester.longPress(_tile(tester, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save that sticker. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Removed from Saved'), findsNothing);
    });

    testWidgets('names the shelf in the language in use', (tester) async {
      await _show(
        tester,
        _harness(Stream.value(const []), locale: const Locale('ar')),
      );

      expect(find.text('مالكش ملصقات محفوظة'), findsOneWidget);
    });

    testWidgets('a shelf that cannot be read offers the read again', (
      tester,
    ) async {
      await _show(
        tester,
        _harness(Stream.error(Exception('permission-denied'))),
      );

      expect(
        find.text('The Saved stickers did not load. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a load still running paints the spinner, not an empty shelf', (
      tester,
    ) async {
      // A stream that has said nothing yet: the panel must not call that empty,
      // because the user would be told to save a sticker they already saved.
      final shelf = StreamController<List<SavedSticker>>();
      addTearDown(shelf.close);
      // The spinner turns forever, so this cannot wait for the frames to settle.
      await tester.pumpWidget(_harness(shelf.stream));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No saved stickers yet'), findsNothing);
    });
  });

  group('the save row in the thread', () {
    final screen = _read('lib/features/chat/chat_screen.dart');

    test('appears only for a sticker a shelf can hold', () {
      expect(screen, contains('ChatFeatures.bundledStickers'));
      expect(screen, contains('SavedSticker.fromStickerId(message.stickerId)'));
      expect(screen, contains('if (savableSticker != null)'));
    });

    test('each outcome of a save is said out loud', () {
      expect(
        screen,
        contains('SavedStickerOutcome.saved => s.savedStickerDone'),
      );
      expect(screen, contains('s.savedStickerFull('));
      expect(
        screen,
        contains('SavedStickerOutcome.unknownSticker => s.savedStickerFailed'),
      );
    });

    test('the row and the case are wired to the same action', () {
      expect(screen, contains('_MessageAction.saveSticker'));
      expect(screen, contains('await _saveSticker(message);'));
    });
  });

  test('the tray leads with the shelf and reuses the sticker sender', () {
    final tray = _read('lib/features/chat/chat_tray.dart');
    expect(tray, contains('enum ChatTrayTab { saved, stickers, emoji, gif }'));
    expect(
      tray,
      contains(
        'ChatTrayTab.saved => ChatSavedStickerPicker(onSelected: widget.onSticker)',
      ),
    );
    expect(
      tray,
      contains(
        'if (ChatFeatures.bundledStickers && !ChatMessageType.sticker.isGated)',
      ),
    );
  });

  test('a bookmark is drawn from the asset of its own reference', () {
    final picker = _read('lib/features/chat/chat_saved_sticker_picker.dart');
    expect(picker, contains('sticker.asset'));
    expect(picker, contains('onSelected(sticker.stickerId)'));
    // No upload path, no download path: the shelf never touches Storage.
    expect(picker, isNot(contains('FirebaseStorage')));
    expect(picker, isNot(contains('mediaUrl')));
  });
}
