import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The knot itself is the glass material, not an opaque glyph on a glass disc.
/// UIKit masks its live backdrop with the bundled logo's alpha channel.
class SmallUGlassLogo extends StatelessWidget {
  const SmallUGlassLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: Platform.isIOS && !kIsWeb
          ? SmallUNativeGlassLogo(dark: dark)
          : Center(
              // Raster-only preview for non-iOS widget tests. Real material
              // acceptance must run on UIKit; this is not a blur substitute.
              child: Image.asset(
                'assets/branding/small_u_light.png',
                key: const ValueKey('small-u-glass-preview'),
                width: 44,
                height: 44,
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.35,
                ),
                excludeFromSemantics: true,
              ),
            ),
    );
  }
}

@visibleForTesting
class SmallUNativeGlassLogo extends StatelessWidget {
  const SmallUNativeGlassLogo({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => UiKitView(
    // A changed appearance recreates the immutable native material parameters.
    key: ValueKey('small-u-native-glass-$dark'),
    viewType: 'ispace/small_u_glass_logo',
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    creationParams: <String, Object>{'dark': dark, 'logoExtent': 44.0},
    creationParamsCodec: const StandardMessageCodec(),
  );
}
