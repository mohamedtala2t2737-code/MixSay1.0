import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/app_list_tile.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
import 'package:social_chat/features/chat/chat_providers.dart';
import 'package:social_chat/features/stories/data/story_repository.dart';
import 'package:social_chat/features/stories/presentation/story_providers.dart';

/// Full-screen story player: auto-advances every 4 seconds, taps on the trailing
/// third move forward, taps on the leading third move back.
class StoryViewerPage extends ConsumerStatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.groups,
    required this.initialIndex,
    this.currentUserId,
  });

  final List<StoryGroup> groups;
  final int initialIndex;
  final String? currentUserId;

  @override
  ConsumerState<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends ConsumerState<StoryViewerPage> {
  static const _storyDuration = Duration(milliseconds: 4000);
  static const _tick = Duration(milliseconds: 33);

  /// How far down the drag has taken the picture before it is a close gesture.
  static const _closeDrag = 140.0;

  late List<StoryGroup> _groups;
  late List<Story> _items;
  late int _position;

  final _reply = TextEditingController();
  bool _sendingReply = false;
  double _drag = 0;

  /// Only the active progress bar listens to this, so the 33ms ticker no longer
  /// rebuilds the whole page (image, header, buttons) 30 times a second.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  Timer? _ticker;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _groups = widget.groups;
    _rebuild();
    _position = _startPosition();
    _startTicker();
    _reportViewed();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _progress.dispose();
    _reply.dispose();
    super.dispose();
  }

  int _startPosition() {
    var offset = 0;
    for (var index = 0; index < widget.initialIndex; index++) {
      offset += _groups[index].stories.length;
    }
    return offset.clamp(0, _items.length - 1);
  }

  /// Keeps [_items] and the group boundaries in step with [_groups].
  void _rebuild() {
    _items = _groups.expand((group) => group.stories).toList();
  }

  int get _groupIndex {
    var offset = 0;
    for (var index = 0; index < _groups.length; index++) {
      final length = _groups[index].stories.length;
      if (_position < offset + length) return index;
      offset += length;
    }
    return _groups.length - 1;
  }

  StoryGroup get _currentGroup => _groups[_groupIndex];
  Story get _currentStory => _items[_position];

  /// Position of the current story inside its own group, which is what the
  /// progress row shows.
  int get _storyIndexInGroup {
    var offset = 0;
    for (var index = 0; index < _groupIndex; index++) {
      offset += _groups[index].stories.length;
    }
    return _position - offset;
  }

  void _startTicker() {
    _ticker?.cancel();
    if (_paused) return;
    _ticker = Timer.periodic(_tick, (timer) {
      final elapsed = _tick.inMilliseconds / _storyDuration.inMilliseconds;
      final next = _progress.value + elapsed;
      if (next >= 1) {
        _advance();
      } else {
        _progress.value = next;
      }
    });
  }

  void _pause() {
    _paused = true;
    _ticker?.cancel();
  }

  void _resume() {
    _paused = false;
    _startTicker();
  }

  /// Tells the author their story was watched. A failed write is only logged:
  /// the audience list is a nicety, and the viewer must never stop over it.
  void _reportViewed() {
    final story = _currentStory;
    ref.read(storyRepositoryProvider).markViewed(story).catchError((
      error,
      stackTrace,
    ) {
      debugPrint('Unable to record the view of ${story.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
    });
  }

  void _advance() {
    if (_position + 1 >= _items.length) {
      _close();
      return;
    }
    _progress.value = 0;
    setState(() {
      _position += 1;
    });
    _startTicker();
    _reportViewed();
  }

  void _rewind() {
    if (_position == 0) return;
    _progress.value = 0;
    setState(() {
      _position -= 1;
    });
    _startTicker();
    _reportViewed();
  }

  void _close() {
    _ticker?.cancel();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _deleteCurrentStory() async {
    final s = AppStrings.of(context);
    final story = _currentStory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeStory),
        content: Text(s.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.deletePost),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(storyRepositoryProvider).deleteStory(story);
    } catch (error, stackTrace) {
      debugPrint('Unable to delete the story: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
      return;
    }

    ref.invalidate(activeStoriesProvider);
    final rebuilt = <StoryGroup>[];
    for (final group in _groups) {
      final remaining = group.stories
          .where((item) => item.id != story.id)
          .toList(growable: false);
      if (remaining.isNotEmpty) {
        rebuilt.add(StoryGroup(authorId: group.authorId, stories: remaining));
      }
    }
    _progress.value = 0;
    setState(() {
      _groups = rebuilt;
      _rebuild();
      _position = _position.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    });
    if (_items.isEmpty) {
      _close();
    } else {
      _startTicker();
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sendingReply) return;
    final s = AppStrings.of(context);
    final story = _currentStory;
    setState(() => _sendingReply = true);
    try {
      // A reply is an ordinary chat message to the author, so it lands in the
      // thread the two already have instead of a new collection the rules do
      // not know about.
      final chat = ref.read(chatRepositoryProvider);
      final conversationId = await chat.getOrCreateConversation(story.authorId);
      await chat.sendMessage(
        conversationId: conversationId,
        text: text,
        clientId: chat.createClientId(),
      );
      _reply.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.replySent)));
    } catch (error, stackTrace) {
      debugPrint('Unable to reply to the story: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.actionFailed)));
      }
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  /// Opens the audience of my own story: who watched this one picture.
  void _openViewers() {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final viewers = ref
        .read(storyRepositoryProvider)
        .viewersOf(_currentStory.id);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  s.storyViewers,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<StoryViewer>>(
                  future: viewers,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrint(
                        'Unable to read the audience: ${snapshot.error}',
                      );
                      return Center(child: Text(s.loadFailed));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final list = snapshot.data!;
                    if (list.isEmpty) {
                      return Center(child: Text(s.noViewers));
                    }
                    return ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final viewer = list[index];
                        final viewedAt = viewer.viewedAt;
                        return AppListTile(
                          leading: UserAvatar(
                            name: viewer.displayName,
                            url: viewer.avatarUrl,
                            radius: 20,
                          ),
                          title: viewer.username,
                          subtitle: viewedAt == null
                              ? null
                              : timeAgo(viewedAt, isArabic: s.isArabic),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(double dx, double width) {
    // In RTL the story order runs right to left, so the rewind strip moves to
    // the right edge instead of the left one.
    final distanceFromStart = Directionality.of(context) == TextDirection.rtl
        ? width - dx
        : dx;
    if (distanceFromStart < width * 0.35) {
      _rewind();
    } else {
      _advance();
    }
  }

  void _onDragUpdate(double deltaY) {
    final next = _drag + deltaY;
    if (next == _drag) return;
    setState(() => _drag = next);
  }

  /// Letting go halfway down closes the story; anything else snaps back.
  /// A fast flick counts as a drag that reached the threshold, because the
  /// pointer never gets there.
  void _onDragEnd(double velocity) {
    if (_drag >= _closeDrag || velocity > 900) {
      _close();
      return;
    }
    setState(() => _drag = 0);
  }

  /// A drag that starts by moving sideways belongs to nothing here, so only the
  /// vertical component drives the close gesture.
  bool _isDownward(Offset delta) => delta.dy.abs() > delta.dx.abs();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final story = _currentStory;
    final group = _currentGroup;
    final activeIndex = _storyIndexInGroup;
    final isMine = story.authorId == widget.currentUserId;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: isMine ? null : _replyBar(s),
      body: Transform.translate(
        offset: Offset(0, _drag),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  _handleTap(details.globalPosition.dx, width),
              onLongPressStart: (_) => _pause(),
              onLongPressEnd: (_) => _resume(),
              onVerticalDragUpdate: (details) {
                if (_isDownward(details.delta)) {
                  _onDragUpdate(details.delta.dy);
                }
              },
              onVerticalDragEnd: (details) =>
                  _onDragEnd(details.primaryVelocity ?? 0),
              child: CachedNetworkImage(
                imageUrl: story.mediaUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < group.stories.length;
                          index++
                        )
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: index == activeIndex
                                  ? _LiveProgressBar(progress: _progress)
                                  : _ProgressBar(
                                      value: index < activeIndex ? 1 : 0,
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                    child: Row(
                      children: [
                        UserAvatar(
                          name: group.displayName,
                          url: group.avatarUrl,
                          radius: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                timeAgo(story.createdAt, isArabic: s.isArabic),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isMine)
                          IconButton(
                            tooltip: s.storyViewers,
                            onPressed: _openViewers,
                            icon: const Icon(
                              Icons.people_outline,
                              color: Colors.white,
                            ),
                          ),
                        if (isMine)
                          IconButton(
                            tooltip: s.removeStory,
                            onPressed: _deleteCurrentStory,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                          ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonLabel,
                          onPressed: _close,
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The reply box sits under the picture, so a long caption never covers it.
  /// Own stories have nobody to reply to, so the bar is not shown at all.
  Widget _replyBar(AppStrings s) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _reply,
                enabled: !_sendingReply,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: s.storyReply,
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white12,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: s.send,
              onPressed: _sendingReply ? null : _sendReply,
              icon: Icon(
                _sendingReply ? Icons.hourglass_empty : Icons.send_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => _storyBar(value);
}

/// The bar of the story that is playing. It listens to the ticker on its own so
/// that 33ms updates never rebuild the rest of the page.
class _LiveProgressBar extends StatelessWidget {
  const _LiveProgressBar({required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) => _storyBar(value),
    );
  }
}

Widget _storyBar(double value) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        Container(height: 3, color: Colors.white24),
        FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(height: 3, color: Colors.white),
        ),
      ],
    ),
  );
}
