import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/features/feed/data/feed_repository.dart';
import 'package:social_chat/features/feed/presentation/saved_posts_provider.dart';
import 'package:social_chat/features/home/presentation/widgets/post_card.dart';

const _post = FeedPost(
  id: 'post-1',
  authorId: 'author-1',
  username: 'layla.hassan',
  fullName: 'Layla Hassan',
  caption: 'Slow moments in Cairo',
  likesCount: 249,
  commentsCount: 3,
  createdAt: null,
  artworkVariant: 0,
  isLiked: false,
  mediaType: 'none',
);

Widget _harness(Locale locale) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: const Scaffold(body: PostCard(post: _post)),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the English card shows the author, counters and actions', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('layla.hassan'), findsOneWidget);
    expect(find.text('Slow moments in Cairo'), findsOneWidget);
    expect(find.text('249 likes'), findsOneWidget);
    expect(find.text('3 comments'), findsOneWidget);
    for (final tooltip in ['Like', 'Comments', 'Share', 'Save']) {
      expect(find.byTooltip(tooltip), findsWidgets);
    }
  });

  testWidgets('saving a post is remembered in Arabic locale too', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('249 إعجاب'), findsOneWidget);
    expect(find.text('3 تعليق'), findsOneWidget);

    await tester.tap(find.byTooltip('حفظ'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('إلغاء الحفظ'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('saved_post_ids'), contains('post-1'));
  });

  test('saved posts restore from preferences', () async {
    SharedPreferences.setMockInitialValues({
      'saved_post_ids': ['post-9', 'post-1'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(savedPostsProvider.notifier).restore();
    expect(container.read(savedPostsProvider), {'post-9', 'post-1'});
  });
}
