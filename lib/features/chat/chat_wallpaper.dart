import 'package:flutter/material.dart';

import 'package:social_chat/core/theme/app_colors.dart';

/// The thread's background: a flat colour with an original lattice of small
/// rings and dots painted over it, so the chat reads as a wallpaper without
/// anything behind it fighting the text for attention.
///
/// Painted rather than shipped as a picture because it then holds at every
/// screen size, follows the theme without a second asset, and costs no bundle
/// bytes. The ink sits at a few percent opacity, which is the whole reason the
/// pattern can stay behind a thread and still leave both bubble colours legible.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final light = brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.chatWallpaper(brightness)),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ChatPatternPainter(
            ink: (light ? AppColors.textOnLight : AppColors.textOnDark)
                .withValues(alpha: light ? 0.05 : 0.04),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  const _ChatPatternPainter({required this.ink});

  final Color ink;

  /// One lattice cell, and the ring and dot inside it.
  static const double _cell = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink;
    final dot = Paint()
      ..style = PaintingStyle.fill
      ..color = ink;
    for (var row = 0.0; row * _cell < size.height + _cell; row++) {
      final y = row * _cell;
      // Every other row steps half a cell aside, which keeps the eye from
      // reading the pattern as a ruled grid.
      final x0 = row % 2 == 0 ? 0.0 : _cell / 2;
      for (
        var column = 0.0;
        (x0 + column * _cell) < size.width + _cell;
        column++
      ) {
        final x = x0 + column * _cell;
        canvas.drawCircle(Offset(x, y), 5, ring);
        canvas.drawCircle(Offset(x + _cell / 2, y + _cell / 2), 1.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_ChatPatternPainter oldDelegate) => oldDelegate.ink != ink;
}
