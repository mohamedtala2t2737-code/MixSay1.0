import 'dart:async';

import 'package:flutter/material.dart';

import 'package:social_chat/features/splash/presentation/splash_view.dart';

/// بيحط الـ Splash فوق التطبيق لمدة قصيرة، وبعدها بيختفي بنعومة.
/// التطبيق نفسه (الراوتر وFirebase والإشعارات) بيشتغل تحتها عادي،
/// فمفيش حاجة في التنقل بتتغير.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2200),
  });

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: _showSplash
                ? const AbsorbPointer(
                    key: ValueKey('splash'),
                    child: SplashView(),
                  )
                : const SizedBox.shrink(key: ValueKey('no-splash')),
          ),
        ),
      ],
    );
  }
}
