import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/features/feed/presentation/home_feed_screen.dart';

void main() {
  testWidgets('shows the dark English home feed and opens the post composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: HomeFeedScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MixSay'), findsOneWidget);
    expect(find.text('Your story'), findsOneWidget);
    expect(find.text('layla.hassan'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(
      tester.getCenter(find.byTooltip('Create a post')).dx,
      closeTo(195, 1),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.home_filled)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.mail_outline_rounded)).dx),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.mail_outline_rounded)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.add_rounded)).dx),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.add_rounded)).dx,
      lessThan(
        tester.getCenter(find.byIcon(Icons.notifications_none_rounded)).dx,
      ),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.notifications_none_rounded)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.account_circle_outlined)).dx),
    );

    await tester.tap(find.byTooltip('Like').first);
    await tester.pumpAndSettle();
    expect(find.text('249 Like'), findsOneWidget);
    await tester.tap(find.byTooltip('Save post').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove saved post').first, findsOneWidget);

    await tester.tap(find.byTooltip('Create a post'));
    await tester.pumpAndSettle();
    expect(find.text('What would you like to share?'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Posts here are a design preview. Publishing will be available soon.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('supports Arabic RTL labels and layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: _LocalizedFeedApp(initialLocale: Locale('ar')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('قصتك'), findsOneWidget);
    expect(find.textContaining('لحظات هادئة'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(HomeFeedScreen))),
      TextDirection.rtl,
    );
    expect(
      tester.getCenter(find.byIcon(Icons.home_filled)).dx,
      greaterThan(tester.getCenter(find.byIcon(Icons.mail_outline_rounded)).dx),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.mail_outline_rounded)).dx,
      greaterThan(tester.getCenter(find.byIcon(Icons.add_rounded)).dx),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.add_rounded)).dx,
      greaterThan(
        tester.getCenter(find.byIcon(Icons.notifications_none_rounded)).dx,
      ),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.notifications_none_rounded)).dx,
      greaterThan(
        tester.getCenter(find.byIcon(Icons.account_circle_outlined)).dx,
      ),
    );

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Your story'), findsOneWidget);
    expect(find.textContaining('Slow moments'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(HomeFeedScreen))),
      TextDirection.ltr,
    );
  });
}

class _LocalizedFeedApp extends ConsumerWidget {
  const _LocalizedFeedApp({required this.initialLocale});

  final Locale initialLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    locale: ref.watch(localeControllerProvider) ?? initialLocale,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppStrings.supportedLocales,
    home: const HomeFeedScreen(),
  );
}
