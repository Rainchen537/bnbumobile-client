import 'package:flutter/material.dart';

import 'bnbu_adaptive.dart';

/// Shared gutters for native iSpace course content, excluding navigation and
/// original web/file canvases.
class IspaceContentPadding extends StatelessWidget {
  const IspaceContentPadding({
    super.key,
    required this.child,
    this.top = 0,
    this.bottom = 0,
  });

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset =
          BnbuBreakpoints.fromWidth(constraints.maxWidth) ==
              BnbuWindowClass.compact
          ? 16.0
          : 24.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, top, inset, bottom),
        child: child,
      );
    },
  );
}
