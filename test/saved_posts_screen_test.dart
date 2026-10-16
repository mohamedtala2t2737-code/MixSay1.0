import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_theme.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/profile/presentation/saved_posts_screen.dart';

class _Saved extends SavedPostsController {
  _Saved(this._ids);

  final Set<String> _ids;

  @override
  Set<String> build() => _ids;
}

FeedPost _post(String id) => FeedPost(
  id: id,
  authorId: 'user-me',
  username: 'mixsay.user',
  fullName: 'MixSay User',
  caption: 'Caption $id',
  likesCount: 0,
  commentsCount: 0,
  createdAt: DateTime(2026, 10, 15),
  artworkVariant: 1,
  isLiked: false,
  mediaUrl: 'https://example.com/$id.jpg',
);

Widget _harness({required Set<String> saved, required List<FeedPost> posts}) {
  return ProviderScope(
    overrides: [
      savedPostsProvider.overrideWith(() => _Saved(saved)),
      feedPostsProvider.overrideWith((ref) => Stream.value(posts)),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: const SavedPostsScreen(),
    ),
  );
}

void main() {
  testWidgets('the saved wall lists only the posts this device saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(saved: const {'a'}, posts: [_post('a'), _post('b'), _post('c')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('a device with no saves says so', (tester) async {
    await tester.pumpWidget(_harness(saved: const {}, posts: [_post('a')]));
    await tester.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
