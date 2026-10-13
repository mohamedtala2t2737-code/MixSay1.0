import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/l10n/locale_providers.dart';
import 'package:social_chat/core/theme/app_colors.dart';
import 'package:social_chat/core/widgets/mixsay_logo.dart';
import 'package:social_chat/core/widgets/primary_button.dart';
import 'package:social_chat/features/auth/presentation/auth_providers.dart';
import 'package:social_chat/features/feed/presentation/feed_providers.dart';

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  ThemeData _darkFeedTheme() {
    final darkTheme = ThemeData.dark(useMaterial3: true);
    return darkTheme.copyWith(
      scaffoldBackgroundColor: AppColors.feedBackground,
      colorScheme: darkTheme.colorScheme.copyWith(
        primary: AppColors.brandPurple,
        onPrimary: Colors.white,
        secondary: AppColors.brandOrange,
        surface: AppColors.feedSurface,
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFB3B3B8),
        outlineVariant: const Color(0xFF343438),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSearch(AppStrings strings) async {
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final posts = ref.read(feedPostsProvider).values;
          final matches = posts
              .where(
                (post) =>
                    post
                        .name(strings)
                        .toLowerCase()
                        .contains(query.toLowerCase()) ||
                    post.username.toLowerCase().contains(query.toLowerCase()) ||
                    post
                        .caption(strings)
                        .toLowerCase()
                        .contains(query.toLowerCase()),
              )
              .toList();
          return AlertDialog(
            title: Text(strings.searchFeed),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) => setDialogState(() => query = value),
                    decoration: InputDecoration(
                      hintText: strings.searchFeedHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(strings.searchFeedEmpty),
                    )
                  else
                    ...matches.map(
                      (post) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _StoryAvatar(
                          name: post.name(strings),
                          color: _storyColors[post.artworkVariant],
                          size: 42,
                        ),
                        title: Text(post.name(strings)),
                        subtitle: Text('@${post.username}'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(strings.cancel),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onMenuAction(String action, AppStrings strings) async {
    if (action == 'language') {
      ref
          .read(localeControllerProvider.notifier)
          .toggle(Localizations.localeOf(context));
      return;
    }
    if (action != 'logout') return;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (error, stackTrace) {
      debugPrint('Unable to sign out: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage(strings.actionFailed);
    }
  }

  Future<void> _showCreatePost(AppStrings strings) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.createPost,
              style: Theme.of(sheetContext).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: strings.postCaptionHint,
                filled: true,
                fillColor: AppColors.feedSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showMessage(strings.feedPreviewOnly),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(strings.attachPhoto),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: strings.share,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _showMessage(strings.feedPreviewOnly);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showComments(String postId, AppStrings strings) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: strings.writeComment,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isEmpty) return;
                  ref.read(feedPostsProvider.notifier).addComment(postId);
                  Navigator.of(sheetContext).pop();
                  _showMessage(strings.commentAdded);
                },
              ),
            ),
            IconButton(
              tooltip: strings.send,
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                ref.read(feedPostsProvider.notifier).addComment(postId);
                Navigator.of(sheetContext).pop();
                _showMessage(strings.commentAdded);
              },
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showStory(String name, AppStrings strings) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 0.62,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandBlue,
                  AppColors.brandPurple,
                  AppColors.brandOrange,
                ],
              ),
            ),
            child: Stack(
              children: [
                PositionedDirectional(
                  top: 18,
                  start: 16,
                  end: 16,
                  child: Row(
                    children: [
                      _StoryAvatar(
                        name: name,
                        color: AppColors.brandGradient.colors,
                        size: 42,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      strings.storyComingSoon,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = _darkFeedTheme();
    final posts = ref.watch(feedPostsProvider).values.toList(growable: false);
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: AppColors.feedBackground,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _FeedHeader(
                      onMenuAction: (action) => _onMenuAction(action, strings),
                      onSearch: () => _showSearch(strings),
                      strings: strings,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _StoriesStrip(
                      strings: strings,
                      onStoryTap: (name) => _showStory(name, strings),
                    ),
                  ),
                  SliverList.separated(
                    itemCount: posts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 22),
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      return _FeedPostCard(
                        post: post,
                        strings: strings,
                        onLike: () => ref
                            .read(feedPostsProvider.notifier)
                            .toggleLike(post.id),
                        onComment: () => _showComments(post.id, strings),
                        onShare: () => _showMessage(strings.shareComingSoon),
                        onSave: () => ref
                            .read(feedPostsProvider.notifier)
                            .toggleSaved(post.id),
                        onMenuAction: (action) {
                          if (action == 'save') {
                            ref
                                .read(feedPostsProvider.notifier)
                                .toggleSaved(post.id);
                          } else if (action == 'share') {
                            _showMessage(strings.shareComingSoon);
                          }
                        },
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: _CurvedBottomBar(
          strings: strings,
          onHome: () {},
          onMessages: () => context.push('/conversations'),
          onCreate: () => _showCreatePost(strings),
          onNotifications: () => _showMessage(strings.notificationsComingSoon),
          onProfile: () => _showMessage(strings.profileComingSoon),
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.strings,
    required this.onMenuAction,
    required this.onSearch,
  });

  final AppStrings strings;
  final ValueChanged<String> onMenuAction;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: strings.changeLanguage,
            onSelected: onMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'language',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.translate),
                  title: Text(strings.changeLanguage),
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text(strings.logOut),
                ),
              ),
            ],
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.menu_rounded),
            ),
          ),
          const Expanded(
            child: Center(
              child: MixSayLogo(
                iconSize: 30,
                fontSize: 29,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          IconButton(
            tooltip: strings.searchFeed,
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded, size: 27),
          ),
        ],
      ),
    );
  }
}

const _storyColors = <List<Color>>[
  [Color(0xFFFB7C45), Color(0xFFE54383), Color(0xFF7F42D8)],
  [Color(0xFF23B8B5), Color(0xFF3E7CE8), Color(0xFF9855E8)],
  [Color(0xFFF0A448), Color(0xFFE5505E), Color(0xFF9B49D6)],
  [Color(0xFF65C96E), Color(0xFF17AFA8), Color(0xFF4A7FE0)],
  [Color(0xFFEB6F98), Color(0xFF9D53D9), Color(0xFF536EE5)],
];

class _StoriesStrip extends StatelessWidget {
  const _StoriesStrip({required this.strings, required this.onStoryTap});

  final AppStrings strings;
  final ValueChanged<String> onStoryTap;

  @override
  Widget build(BuildContext context) {
    final people = [
      (strings.yourStory, true),
      (strings.sampleAuthorName, false),
      (strings.sampleSecondAuthorName, false),
      (strings.isArabic ? 'نور علي' : 'Noor Ali', false),
      (strings.isArabic ? 'مريم' : 'Mariam', false),
      (strings.isArabic ? 'يوسف' : 'Youssef', false),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 14),
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final (name, isOwnStory) = people[index];
          return SizedBox(
            width: 66,
            child: InkWell(
              borderRadius: BorderRadius.circular(36),
              onTap: () =>
                  isOwnStory ? onStoryTap(strings.yourStory) : onStoryTap(name),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _StoryAvatar(
                        name: name,
                        color: _storyColors[index % _storyColors.length],
                        size: 64,
                        muted: isOwnStory,
                      ),
                      if (isOwnStory)
                        PositionedDirectional(
                          bottom: -1,
                          end: -1,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.feedBackground,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    isOwnStory ? strings.yourStory : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.name,
    required this.color,
    required this.size,
    this.muted = false,
  });

  final String name;
  final List<Color> color;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        gradient: muted
            ? const LinearGradient(
                colors: [Color(0xFF6C6C72), Color(0xFF38383D)],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: color,
              ),
        shape: BoxShape.circle,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.feedBackground,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.feedBackground, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: color,
            ),
          ),
          child: Center(
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on FeedPostState {
  String name(AppStrings strings) =>
      id == 'layla' ? strings.sampleAuthorName : strings.sampleSecondAuthorName;

  String caption(AppStrings strings) => id == 'layla'
      ? strings.samplePostCaption
      : strings.sampleSecondPostCaption;
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.strings,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onMenuAction,
  });

  final FeedPostState post;
  final AppStrings strings;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final ValueChanged<String> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 10),
          child: Row(
            children: [
              _StoryAvatar(
                name: post.name(strings),
                color: _storyColors[post.artworkVariant],
                size: 42,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.username,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.postLocation,
                      style: textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFB3B3B8),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: strings.postOptions,
                onSelected: onMenuAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'save',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        post.saved ? Icons.bookmark_remove : Icons.bookmark_add,
                      ),
                      title: Text(
                        post.saved ? strings.unsavePost : strings.savePost,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.send_outlined),
                      title: Text(strings.share),
                    ),
                  ),
                ],
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.more_horiz_rounded),
                ),
              ),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 0.94,
          child: ClipRRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _PostArtworkPainter(post.artworkVariant)),
                PositionedDirectional(
                  top: 20,
                  start: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MIXSAY',
                        style: textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          letterSpacing: 4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 210,
                        child: Text(
                          post.artworkVariant == 0
                              ? 'A LITTLE SPACE TO BREATHE'
                              : 'CHASING THE SOFT LIGHT',
                          style: textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const PositionedDirectional(
                  top: 14,
                  end: 14,
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                PositionedDirectional(
                  bottom: 18,
                  start: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      strings.postLocation,
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: strings.likes,
                onPressed: onLike,
                icon: Icon(
                  post.liked ? Icons.favorite : Icons.favorite_border_rounded,
                  color: post.liked ? const Color(0xFFFF5577) : Colors.white,
                ),
              ),
              IconButton(
                tooltip: strings.comments,
                onPressed: onComment,
                icon: const Icon(Icons.mode_comment_outlined),
              ),
              IconButton(
                tooltip: strings.share,
                onPressed: onShare,
                icon: const Icon(Icons.send_outlined),
              ),
              const Spacer(),
              IconButton(
                tooltip: post.saved ? strings.unsavePost : strings.savePost,
                onPressed: onSave,
                icon: Icon(
                  post.saved ? Icons.bookmark : Icons.bookmark_border_rounded,
                  color: post.saved ? AppColors.brandOrange : Colors.white,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 2),
          child: Text(
            '${post.likes} ${strings.likes}',
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 5, 16, 0),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${post.username}  ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: post.caption(strings)),
              ],
            ),
            style: textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
        TextButton(
          onPressed: onComment,
          style: TextButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 0),
            foregroundColor: const Color(0xFFB3B3B8),
          ),
          child: Text(strings.commentsCount(post.comments)),
        ),
      ],
    );
  }
}

class _PostArtworkPainter extends CustomPainter {
  const _PostArtworkPainter(this.variant);

  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final isSecond = variant.isOdd;
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isSecond
            ? const [Color(0xFF173B58), Color(0xFF57417E), Color(0xFFE98862)]
            : const [Color(0xFF284A63), Color(0xFF725784), Color(0xFFE99165)],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final sun = Paint()
      ..shader =
          const RadialGradient(colors: [Color(0xFFFFE7A6), Color(0xFFF6B37B)])
              .createShader(
                Rect.fromCircle(
                  center: Offset(size.width * 0.73, size.height * 0.47),
                  radius: size.width * 0.17,
                ),
              );
    canvas.drawCircle(
      Offset(size.width * 0.73, size.height * 0.47),
      size.width * 0.17,
      sun,
    );

    final farMountain = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.55,
        size.width * 0.31,
        size.height * 0.77,
        size.width * 0.52,
        size.height * 0.62,
      )
      ..cubicTo(
        size.width * 0.69,
        size.height * 0.5,
        size.width * 0.82,
        size.height * 0.68,
        size.width,
        size.height * 0.53,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      farMountain,
      Paint()..color = const Color(0xFF574C73).withValues(alpha: 0.82),
    );

    final nearMountain = Path()
      ..moveTo(0, size.height * 0.84)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.68,
        size.width * 0.39,
        size.height * 0.83,
        size.width * 0.61,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.65,
        size.width * 0.88,
        size.height * 0.76,
        size.width,
        size.height * 0.69,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      nearMountain,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF202E42), Color(0xFF352B48)],
        ).createShader(rect),
    );

    final foreground = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF182733), Color(0xFF302534)],
      ).createShader(rect);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.52, size.height * 1.02),
        width: size.width * 1.2,
        height: size.height * 0.34,
      ),
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _PostArtworkPainter oldDelegate) =>
      oldDelegate.variant != variant;
}

class _CurvedBottomBar extends StatelessWidget {
  const _CurvedBottomBar({
    required this.strings,
    required this.onHome,
    required this.onMessages,
    required this.onCreate,
    required this.onNotifications,
    required this.onProfile,
  });

  final AppStrings strings;
  final VoidCallback onHome;
  final VoidCallback onMessages;
  final VoidCallback onCreate;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 76,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _CurvedBarPainter())),
            Positioned.fill(
              top: 18,
              child: Row(
                children: [
                  Expanded(
                    child: _BottomNavAction(
                      label: strings.home,
                      icon: Icons.home_filled,
                      selected: true,
                      onPressed: onHome,
                    ),
                  ),
                  Expanded(
                    child: _BottomNavAction(
                      label: strings.messages,
                      icon: Icons.mail_outline_rounded,
                      onPressed: onMessages,
                    ),
                  ),
                  const SizedBox(width: 72),
                  Expanded(
                    child: _BottomNavAction(
                      label: strings.notifications,
                      icon: Icons.notifications_none_rounded,
                      onPressed: onNotifications,
                    ),
                  ),
                  Expanded(
                    child: _BottomNavAction(
                      label: strings.profile,
                      icon: Icons.account_circle_outlined,
                      onPressed: onProfile,
                    ),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: -8,
              start: 0,
              end: 0,
              child: Center(
                child: Semantics(
                  button: true,
                  label: strings.createPost,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPurple.withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                      gradient: AppColors.brandGradient,
                    ),
                    child: IconButton(
                      tooltip: strings.createPost,
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_rounded, size: 30),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(56, 56),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavAction extends StatelessWidget {
  const _BottomNavAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF9A9AA1);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurvedBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final path = Path()
      ..moveTo(0, 17)
      ..lineTo(center - 54, 17)
      ..cubicTo(center - 35, 17, center - 34, 0, center, 0)
      ..cubicTo(center + 34, 0, center + 35, 17, center + 54, 17)
      ..lineTo(size.width, 17)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.feedSurface);
    final edge = Path()
      ..moveTo(0, 17)
      ..lineTo(center - 54, 17)
      ..cubicTo(center - 35, 17, center - 34, 0, center, 0)
      ..cubicTo(center + 34, 0, center + 35, 17, center + 54, 17)
      ..lineTo(size.width, 17);
    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xFF303035)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvedBarPainter oldDelegate) => false;
}
