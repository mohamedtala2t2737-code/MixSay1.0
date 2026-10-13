import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class MixSayLogo extends StatelessWidget {
  const MixSayLogo({
    super.key,
    this.iconSize = 44,
    this.fontSize = 36,
    this.fontStyle = FontStyle.normal,
    this.showIcon = true,
  });

  final double iconSize;
  final double fontSize;
  final FontStyle fontStyle;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Image.asset(
              'assets/images/mixsay_logo.png',
              width: iconSize,
              height: iconSize,
            ),
            const SizedBox(width: 10),
          ],
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.brandGradient.createShader(bounds),
            child: Text(
              'MixSay',
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                fontStyle: fontStyle,
                letterSpacing: -1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
