import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:social_chat/core/l10n/app_strings.dart';

/// A post video with a real player: tap once to play, tap again to pause.
///
/// Initialization is async and can fail on a bad URL or an unsupported codec,
/// so the widget never assumes it will get a frame: it shows a spinner, then
/// either the player or a retryable error tile.
class PostVideo extends StatefulWidget {
  const PostVideo({super.key, required this.url});

  final String url;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

enum _Stage { loading, ready, failed }

/// The indicator is clipped to a real 3 px band: given more height it paints an
/// indeterminate sweep animation, which never stops and never settles.
const double _seekBarHeight = 3;

class _PostVideoState extends State<PostVideo> {
  VideoPlayerController? _controller;
  _Stage _stage = _Stage.loading;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(PostVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _open();
  }

  Future<void> _open() async {
    final previous = _controller;
    _controller = null;
    if (previous != null) _release(previous);
    if (!mounted) return;
    setState(() => _stage = _Stage.loading);

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        _release(controller);
        return;
      }
      controller.addListener(_onTick);
      setState(() {
        _controller = controller;
        _stage = _Stage.ready;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to open the post video: $error');
      debugPrintStack(stackTrace: stackTrace);
      _release(controller);
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  /// A controller whose `initialize()` threw can leave `dispose()` waiting on a
  /// completer that never completes, so it is deliberately not awaited here:
  /// awaiting it would keep the tile spinning forever instead of showing the
  /// retry message.
  void _release(VideoPlayerController controller) {
    controller.removeListener(_onTick);
    controller.dispose().catchError((Object _) {});
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) _release(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final controller = _controller;

    if (controller == null) {
      return _Frame(
        color: theme.colorScheme.surfaceContainerHighest,
        // No fixed height: at large text scales the retry tile must be able to
        // grow instead of clipping its own message.
        minHeight: 180,
        child: _stage == _Stage.loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.videoUnavailable,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    TextButton(onPressed: _open, child: Text(s.retry)),
                  ],
                ),
              ),
      );
    }

    final ratio = controller.value.aspectRatio;
    return _Frame(
      color: Colors.black,
      aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(controller),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Semantics(
                button: true,
                label: controller.value.isPlaying ? s.pauseVideo : s.playVideo,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: controller.value.isPlaying ? 0 : 1,
                  child: ColoredBox(
                    color: Colors.black38,
                    child: const Center(
                      child: Icon(Icons.play_arrow_rounded, size: 60),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _seekBarHeight,
            child: ClipRect(
              child: SizedBox(
                height: _seekBarHeight,
                child: LinearProgressIndicator(
                  minHeight: _seekBarHeight,
                  value: controller.value.duration.inMilliseconds > 0
                      ? controller.value.position.inMilliseconds /
                            controller.value.duration.inMilliseconds
                      : 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.color,
    this.aspectRatio,
    this.minHeight,
    required this.child,
  });

  final Color color;
  final double? aspectRatio;
  final double? minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final box = ColoredBox(
      color: color,
      child: Center(child: child),
    );
    final ratio = aspectRatio;
    if (ratio != null) return AspectRatio(aspectRatio: ratio, child: box);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight ?? 180),
      child: SizedBox(width: double.infinity, child: box),
    );
  }
}
