import 'dart:async';
import 'package:flutter/material.dart';
import '../services/page_backdrop_store.dart';
import '../theme/app_theme.dart';

class PageBackdrop extends StatefulWidget {
  const PageBackdrop({
    super.key,
    required this.page,
    this.alignment = Alignment.center,
    this.defaultOpacity = 1,
    this.store,
  });
  final String page;
  final Alignment alignment;
  final double defaultOpacity;
  final PageBackdropStore? store;
  @override
  State<PageBackdrop> createState() => _PageBackdropState();
}

class _PageBackdropState extends State<PageBackdrop> {
  PageBackdropStore get store => widget.store ?? PageBackdropStore.shared;
  @override
  void initState() {
    super.initState();
    unawaited(store.start());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final mode = Theme.of(context).brightness == Brightness.dark
          ? 'dark'
          : 'light';
      final slot = '${widget.page}/$mode';
      final bytes = store.bytesFor(slot);
      return Opacity(
        opacity: store.opacityFor(slot) ?? widget.defaultOpacity,
        child: Image(
          key: ValueKey('page-backdrop-$slot'),
          image: bytes == null
              ? AssetImage(PageBackdropStore.defaults[slot]!)
              : MemoryImage(bytes) as ImageProvider,
          fit: BoxFit.cover,
          alignment: widget.alignment,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Image.asset(
            PageBackdropStore.defaults[slot]!,
            fit: BoxFit.cover,
            alignment: widget.alignment,
          ),
        ),
      );
    },
  );
}

/// Artwork/gradient only; page-specific geometry and controls remain unchanged.
class PageHeaderBackdrop extends StatelessWidget {
  const PageHeaderBackdrop({
    super.key,
    required this.page,
    this.translucentTail = 0,
  });
  final String page;
  final double translucentTail;
  @override
  Widget build(BuildContext context) {
    final artwork = ColoredBox(
      color: context.bnbuTheme.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageBackdrop(
            page: page,
            alignment: Alignment.topCenter,
            defaultOpacity: .3,
          ),
          DecoratedBox(
            key: ValueKey('page-header-fade-$page'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .55, 1],
                colors: [
                  context.bnbuTheme.canvas.withValues(alpha: .05),
                  context.bnbuTheme.canvas.withValues(alpha: .4),
                  context.bnbuTheme.canvas,
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (translucentTail == 0) return artwork;
    return IgnorePointer(
      child: ShaderMask(
        key: ValueKey('page-header-translucency-$page'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, (1 - translucentTail / bounds.height).clamp(0.0, 1.0), 1],
          colors: const [Colors.white, Colors.white, Color(0x80ffffff)],
        ).createShader(bounds),
        child: artwork,
      ),
    );
  }
}

/// Measures the fixed header in the same frame and lets the scroll viewport
/// continue beneath its translucent tail. Controls paint above the body.
class PageHeaderOverlay extends StatelessWidget {
  const PageHeaderOverlay({
    super.key,
    required this.header,
    required this.body,
    this.overlap = tailHeight,
  });
  static const double tailHeight = 24;
  final Widget header, body;
  final double overlap;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: CustomMultiChildLayout(
      delegate: _HeaderOverlayLayout(overlap),
      children: [
        LayoutId(id: 'body', child: body),
        LayoutId(id: 'header', child: header),
      ],
    ),
  );
}

class _HeaderOverlayLayout extends MultiChildLayoutDelegate {
  _HeaderOverlayLayout(this.overlap);
  final double overlap;
  @override
  void performLayout(Size size) {
    final header = layoutChild(
      'header',
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final top = (header.height - overlap).clamp(0.0, size.height);
    layoutChild(
      'body',
      BoxConstraints.tight(Size(size.width, size.height - top)),
    );
    positionChild('body', Offset(0, top));
    positionChild('header', Offset.zero);
  }

  @override
  bool shouldRelayout(_HeaderOverlayLayout oldDelegate) =>
      oldDelegate.overlap != overlap;
}
