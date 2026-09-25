import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SmallULogo extends StatelessWidget {
  const SmallULogo({
    super.key,
    this.size = 40,
    this.showRunningRing = false,
    this.monochrome = false,
    this.semanticLabel = '小U',
  });

  final double size;
  final bool showRunningRing;
  final bool monochrome;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final assetName = isDark
        ? 'assets/branding/small_u_dark.png'
        : 'assets/branding/small_u_light.png';
    final logo = SizedBox.square(
      key: const ValueKey('small-u-logo-body'),
      dimension: size,
      child: ColorFiltered(
        colorFilter: monochrome
            ? ColorFilter.mode(
                isDark ? Colors.white : Colors.black,
                BlendMode.srcIn,
              )
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: Image.asset(
          assetName,
          key: ValueKey(isDark ? 'small-u-logo-dark' : 'small-u-logo-light'),
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );

    return Semantics(
      image: true,
      label: context.l10n.text(semanticLabel),
      child: showRunningRing
          ? Container(
              key: const ValueKey('small-u-logo-running-ring'),
              width: size + 8,
              height: size + 8,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white : tokens.brandBlue,
                  width: 2,
                ),
              ),
              child: logo,
            )
          : logo,
    );
  }
}
