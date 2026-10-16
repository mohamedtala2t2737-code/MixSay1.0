import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/chat/chat_gif_search.dart';

/// Localizations load asynchronously, so the frame right after pumpWidget is
/// still an empty box. The last pump carries a sheet or a route transition to
/// its end, which is when the value a popped sheet returned has landed.
Future<void> _show(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  await _settle(tester);
  await tester.pump(const Duration(seconds: 1));
}

Widget _harness(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: Scaffold(body: child),
    );

Map<String, dynamic> _row(
  String id, {
  String? gif,
  String? tiny,
  String? medium,
}) => {
  'id': id,
  'media_formats': {
    if (gif != null) 'gif': {'url': gif},
    if (tiny != null) 'tinygif': {'url': tiny},
    if (medium != null) 'mediumgif': {'url': medium},
  },
};

Map<String, dynamic> _page(List<String> ids, {String? next}) => {
  'results': [
    for (final id in ids) _row(id, gif: 'https://media.tenor.com/$id.gif'),
  ],
  'next': ?next,
};

/// A fetcher that hands back one canned body per call and remembers the urls it
/// was asked for, which is how a test reads the query and the paging cursor.
class _FakeTenor {
  _FakeTenor(this.bodies);

  /// Each entry is either a response body or the error to throw for that call.
  final List<Object> bodies;
  final List<Uri> calls = [];
  int _index = 0;

  Future<Map<String, dynamic>> fetch(Uri uri) async {
    calls.add(uri);
    final body = bodies[_index++];
    if (body is Exception) throw body;
    return body as Map<String, dynamic>;
  }
}

void main() {
  group('tenor request shape', () {
    test('a search carries the query, the key and the next page cursor', () {
      final uri = chatGifSearchUri(
        'happy cat',
        after: 'ABCD',
        apiKey: 'test-key',
      );
      expect(uri.host, 'tenor.googleapis.com');
      expect(uri.path, '/v2/search');
      expect(uri.queryParameters['q'], 'happy cat');
      expect(uri.queryParameters['key'], 'test-key');
      expect(uri.queryParameters['pos'], 'ABCD');
      expect(uri.queryParameters['limit'], '$chatGifPageSize');
    });

    test('the first page asks for no cursor', () {
      final uri = chatGifSearchUri('cat', apiKey: 'test-key');
      expect(uri.queryParameters.containsKey('pos'), isFalse);
    });

    test('the opening grid is trending, which needs no query', () {
      final uri = chatGifTrendingUri(apiKey: 'test-key');
      expect(uri.path, '/v2/trending');
      expect(uri.queryParameters.containsKey('q'), isFalse);
    });
  });

  group('tenor response parsing', () {
    test('a row with no playable gif is dropped, not half-built', () {
      final page = chatGifPageFromTenor({
        'results': [
          _row('keep', gif: 'https://media.tenor.com/keep.gif'),
          {'id': 'noFormats'},
          _row('webpOnly', tiny: 'https://media.tenor.com/keep.webp'),
          'not a row',
        ],
      });
      expect(page.gifs.map((gif) => gif.id), ['keep']);
      expect(page.next, isNull);
    });

    test('a gif is sent whole and a smaller loop previews it', () {
      final page = chatGifPageFromTenor({
        'results': [
          _row(
            'a',
            gif: 'https://media.tenor.com/a.gif',
            tiny: 'https://media.tenor.com/a-tiny.gif',
          ),
          _row('b', gif: 'https://media.tenor.com/b.gif'),
        ],
        'next': 'POS2',
      });
      expect(page.gifs.first.previewUrl, 'https://media.tenor.com/a-tiny.gif');
      expect(page.gifs.first.url, 'https://media.tenor.com/a.gif');
      // With no tiny form the only url has to serve both jobs.
      expect(page.gifs.last.previewUrl, 'https://media.tenor.com/b.gif');
      expect(page.next, 'POS2');
    });

    test('a link the app could not paint is ignored', () {
      final page = chatGifPageFromTenor({
        'results': [
          _row('insecure', gif: 'http://media.tenor.com/a.gif'),
          _row('relative', gif: '/a.gif'),
        ],
      });
      expect(page.gifs, isEmpty);
    });

    test('a body that is not a listing reads as no results', () {
      expect(chatGifPageFromTenor({}).gifs, isEmpty);
      expect(chatGifPageFromTenor({'results': 'oops'}).gifs, isEmpty);
    });
  });

  group('the gif tab', () {
    testWidgets('it opens on trending and paints one tile per gif', (
      tester,
    ) async {
      final tenor = _FakeTenor([_page(['1', '2'])]);
      await _show(
        tester,
        _harness(ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {})),
      );
      await _settle(tester);

      expect(tenor.calls, hasLength(1));
      expect(tenor.calls.single.path, '/v2/trending');
      expect(find.byKey(const ValueKey('gif-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gif-2')), findsOneWidget);
    });

    testWidgets('typing in the field searches instead', (tester) async {
      final tenor = _FakeTenor([_page(['1']), _page(['2'])]);
      await _show(
        tester,
        _harness(ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {})),
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'dancing cat');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);

      expect(tenor.calls.last.queryParameters['q'], 'dancing cat');
      expect(find.byKey(const ValueKey('gif-1')), findsNothing);
      expect(find.byKey(const ValueKey('gif-2')), findsOneWidget);
    });

    testWidgets('no results says so instead of showing a blank grid', (
      tester,
    ) async {
      final tenor = _FakeTenor([_page([])]);
      await _show(
        tester,
        _harness(ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {})),
      );
      await _settle(tester);

      expect(find.text('No GIFs for that search'), findsOneWidget);
    });

    testWidgets('a refused request tries again with the same search', (
      tester,
    ) async {
      final tenor = _FakeTenor([
        const ChatGifSearchFailure(403),
        _page(['1']),
        const ChatGifSearchFailure(500),
        _page(['2']),
      ]);
      await _show(
        tester,
        _harness(ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {})),
      );
      await _settle(tester);

      expect(find.text('Failed to load'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('gif-1')), findsOneWidget);

      // A retry after a real search repeats that search, not the trending
      // default, or the user loses what they were looking for.
      await tester.enterText(find.byType(TextField), 'cat');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      await _settle(tester);

      expect(tenor.calls.last.queryParameters['q'], 'cat');
      expect(find.byKey(const ValueKey('gif-2')), findsOneWidget);
    });

    testWidgets('show more appends the next page and keeps the first', (
      tester,
    ) async {
      final tenor = _FakeTenor([_page(['1'], next: 'POS2'), _page(['2'])]);
      await _show(
        tester,
        _harness(ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {})),
      );
      await _settle(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Show more'));
      await _settle(tester);

      expect(tenor.calls.last.queryParameters['pos'], 'POS2');
      expect(find.byKey(const ValueKey('gif-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gif-2')), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Show more'), findsNothing);
    });

    testWidgets('a tapped gif is what the sheet hands back', (tester) async {
      final tenor = _FakeTenor([_page(['1'])]);
      ChatGif? chosen;
      await _show(
        tester,
        MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    chosen = await showChatGifPicker(
                      context,
                      fetch: tenor.fetch,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await _finish(tester);
      await tester.tap(find.byKey(const ValueKey('gif-1')));
      await _finish(tester);

      expect(chosen?.url, 'https://media.tenor.com/1.gif');
      expect(chosen?.previewUrl, 'https://media.tenor.com/1.gif');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the empty state speaks Arabic when the app does', (
      tester,
    ) async {
      final tenor = _FakeTenor([_page([])]);
      await _show(
        tester,
        _harness(
          ChatGifPicker(fetch: tenor.fetch, onSelected: (_) {}),
          locale: const Locale('ar'),
        ),
      );
      await _settle(tester);

      expect(find.text('مفيش صور متحركة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
