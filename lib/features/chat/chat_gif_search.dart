import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:social_chat/core/config/chat_secrets.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/widgets/states.dart';

/// One GIF a search returned.
///
/// Nothing here is uploaded: the message stores [url] as its media path, which
/// is the one shape `firestore.rules` accepts for a gif, and [previewUrl] is the
/// smaller loop the grid paints.
class ChatGif {
  const ChatGif({
    required this.id,
    required this.url,
    required this.previewUrl,
  });

  final String id;
  final String url;
  final String previewUrl;
}

/// One page of results, plus the cursor that asks for the next one.
typedef ChatGifPage = ({List<ChatGif> gifs, String? next});

/// How a search body is fetched, so a test can hand back canned json.
typedef ChatGifFetcher = Future<Map<String, dynamic>> Function(Uri uri);

/// How many GIFs one request asks for. Tenor caps a page at 50.
const int chatGifPageSize = 20;

const String _tenorHost = 'tenor.googleapis.com';

Uri chatGifSearchUri(
  String query, {
  String? after,
  int limit = chatGifPageSize,
  String apiKey = ChatSecrets.tenorApiKey,
}) => Uri(
  scheme: 'https',
  host: _tenorHost,
  path: '/v2/search',
  queryParameters: {
    'q': query,
    'key': apiKey,
    'client_id': 'mixsay',
    'limit': '$limit',
    'media_filter': 'tinygif,gif',
    if (after != null && after.isNotEmpty) 'pos': after,
  },
);

/// The same listing without a query, which is what the grid shows before the
/// user types anything.
Uri chatGifTrendingUri({
  String? after,
  int limit = chatGifPageSize,
  String apiKey = ChatSecrets.tenorApiKey,
}) => Uri(
  scheme: 'https',
  host: _tenorHost,
  path: '/v2/trending',
  queryParameters: {
    'key': apiKey,
    'client_id': 'mixsay',
    'limit': '$limit',
    'media_filter': 'tinygif,gif',
    if (after != null && after.isNotEmpty) 'pos': after,
  },
);

/// A Tenor response turned into a page.
///
/// A result with no playable gif is dropped instead of half-built: a tile that
/// cannot be tapped is worse than a missing tile, and an old build must never
/// send an empty url that the other side cannot paint.
ChatGifPage chatGifPageFromTenor(Map<String, dynamic> body) {
  final rows = body['results'];
  final gifs = <ChatGif>[
    if (rows is List)
      for (final row in rows)
        if (_gifOf(row) case final ChatGif gif) gif,
  ];
  final next = body['next'];
  return (gifs: gifs, next: next is String && next.isNotEmpty ? next : null);
}

ChatGif? _gifOf(Object? row) {
  if (row is! Map) return null;
  final formats = row['media_formats'];
  if (formats is! Map) return null;
  // Only the full gif may be sent: the smaller forms are previews, and Tenor
  // also lists webp and mp4 next to them, which the gif message type is not.
  final url = _urlOf(formats['gif']);
  if (url == null) return null;
  final id = row['id'];
  if (id is! String || id.isEmpty) return null;
  return ChatGif(
    id: id,
    url: url,
    previewUrl:
        _urlOf(formats['tinygif']) ?? _urlOf(formats['mediumgif']) ?? url,
  );
}

String? _urlOf(Object? format) {
  if (format is! Map) return null;
  final url = format['url'];
  return url is String && url.startsWith('https://') ? url : null;
}

/// Why a search did not come back. The status code is kept so a tester can say
/// which side refused: a bad key and a blocked network look the same on screen.
class ChatGifSearchFailure implements Exception {
  const ChatGifSearchFailure(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'ChatGifSearchFailure: HTTP $statusCode';
}

/// The default [ChatGifFetcher]: one GET, decoded with the text kept as bytes so
/// an emoji in a tag does not come back mojibake.
Future<Map<String, dynamic>> chatGifFetch(Uri uri) async {
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw ChatGifSearchFailure(response.statusCode);
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    throw const ChatGifSearchFailure(0);
  }
  return decoded;
}

/// The GIF tab: a search field over a grid, with its own loading, empty and
/// failed states so a stalled request never looks like an empty library.
class ChatGifPicker extends StatefulWidget {
  const ChatGifPicker({super.key, required this.onSelected, this.fetch});

  /// Receives the GIF the user tapped.
  final ValueChanged<ChatGif> onSelected;

  /// Replaced in tests; production uses [chatGifFetch].
  final ChatGifFetcher? fetch;

  @override
  State<ChatGifPicker> createState() => _ChatGifPickerState();
}

class _ChatGifPickerState extends State<ChatGifPicker> {
  final _controller = TextEditingController();
  List<ChatGif> _gifs = const [];
  String? _next;
  bool _loading = false;
  bool _failed = false;

  /// What the last request was for, so a retry repeats it and "show more" keeps
  /// the same results on screen.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    _query = query;
    setState(() {
      _loading = true;
      _failed = false;
      _gifs = const [];
      _next = null;
    });
    final uri = query.isEmpty ? chatGifTrendingUri() : chatGifSearchUri(query);
    final page = await _request(uri);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page case final ChatGifPage result) {
        _gifs = result.gifs;
        _next = result.next;
      } else {
        _failed = true;
      }
    });
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading) return;
    setState(() => _loading = true);
    final uri = _query.isEmpty
        ? chatGifTrendingUri(after: cursor)
        : chatGifSearchUri(_query, after: cursor);
    final page = await _request(uri);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // The tiles already on screen stay put whatever happens to the next page,
      // so a failed load more only removes the button.
      if (page case final ChatGifPage result) {
        _gifs = [..._gifs, ...result.gifs];
        _next = result.next;
      }
    });
  }

  /// One request and its body turned into a page, or null when it failed.
  Future<ChatGifPage?> _request(Uri uri) async {
    try {
      final body = await (widget.fetch ?? chatGifFetch)(uri);
      if (!mounted) return null;
      return chatGifPageFromTenor(body);
    } catch (error, stackTrace) {
      debugPrint('GIF search failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _search(value.trim()),
            decoration: InputDecoration(
              hintText: strings.searchGifsHint,
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _body(strings)),
      ],
    );
  }

  Widget _body(AppStrings strings) {
    if (_failed && _gifs.isEmpty) {
      return ErrorStateView(
        message: strings.loadFailed,
        onRetry: () => _search(_query),
      );
    }
    if (_gifs.isEmpty && _loading) return const LoadingView();
    if (_gifs.isEmpty) {
      return EmptyStateView(
        icon: Icons.gif_outlined,
        title: strings.noGifsFound,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 1.05,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _gifs.length + (_next == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= _gifs.length) {
          return Center(
            child: TextButton(
              onPressed: _loading ? null : _loadMore,
              child: Text(strings.showMore),
            ),
          );
        }
        final gif = _gifs[index];
        return _GifTile(
          key: ValueKey('gif-${gif.id}'),
          gif: gif,
          onTap: () => widget.onSelected(gif),
        );
      },
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({super.key, required this.gif, required this.onTap});

  final ChatGif gif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return InkWell(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          gif.previewUrl,
          fit: BoxFit.cover,
          semanticLabel: strings.attachGif,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.gif_outlined)),
          ),
        ),
      ),
    );
  }
}

/// Opens the GIF tab and reports what was chosen, or null when it was dismissed.
Future<ChatGif?> showChatGifPicker(
  BuildContext context, {
  ChatGifFetcher? fetch,
}) => showModalBottomSheet<ChatGif>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => SizedBox(
    height: MediaQuery.sizeOf(sheetContext).height * .7,
    child: SafeArea(
      child: ChatGifPicker(
        fetch: fetch,
        onSelected: (gif) => Navigator.of(sheetContext).pop(gif),
      ),
    ),
  ),
);
