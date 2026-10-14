import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/utils/time_ago.dart';
import 'package:social_chat/core/widgets/user_avatar.dart';
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

  late List<StoryGroup> _groups;
  late List<Story> _items;
  late int _position;

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
  }

  void _rewind() {
    if (_position == 0) return;
    _progress.value = 0;
    setState(() {
      _position -= 1;
    });
    _startTicker();
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

  @override
  void dispose() {
    _ticker?.cancel();
    _progress.dispose();
    super.dispose();
  }

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.globalPosition.dx, width),
            onLongPressStart: (_) => _pause(),
            onLongPressEnd: (_) => _resume(),
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
                      for (var index = 0; index < group.stories.length; index++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
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
