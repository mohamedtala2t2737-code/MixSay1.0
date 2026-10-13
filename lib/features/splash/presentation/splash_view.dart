import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:social_chat/core/theme/app_colors.dart';

/// شكل شاشة الـ Splash: خلفية سودة، الشعار، اسم MixSay بالتدرج،
/// توقيع صغير، وخط تحميل متدرج في آخر الشاشة.
class SplashView extends StatelessWidget {
  const SplashView({
    super.key,
    this.loadingDuration = const Duration(milliseconds: 2000),
  });

  final Duration loadingDuration;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          color: Colors.black,
          child: SizedBox.expand(
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOut,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.scale(
                            scale: 0.9 + 0.1 * t,
                            child: child,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/mixsay_logo_splash.png',
                              width: 120,
                              height: 120,
                            ),
                            const SizedBox(height: 20),
                            ShaderMask(
                              shaderCallback: (bounds) =>
                                  AppColors.brandGradient.createShader(bounds),
                              child: const Text(
                                'MixSay',
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    'M.TalaT',
                    style: TextStyle(
                      color: Color(0xFF8A8A93),
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _LoadingLine(duration: loadingDuration),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// خط رفيع بالتدرج الموحد بيتملي من الشمال لليمين.
class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.duration});

  final Duration duration;

  static const double _width = 220;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF1C1C24)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              curve: Curves.easeInOut,
              builder: (context, t, _) => Align(
                alignment: Alignment.centerLeft,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: t,
                    child: const SizedBox(
                      width: _width,
                      height: _height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                        ),
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
