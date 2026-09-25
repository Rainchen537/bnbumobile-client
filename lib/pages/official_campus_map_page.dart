import 'file_preview_page.dart';
import 'dart:async';
import '../services/official_campus_map_store.dart';
import '../widgets/bnbu_loading.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/file_preview_frame.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Public artwork linked by the university's Campus_Map.htm page.
/// Loaded independently of authenticated school clients and WebView sessions.
class OfficialCampusMapPage extends StatefulWidget {
  const OfficialCampusMapPage({super.key, this.image, this.store});

  static const imageUrl = OfficialCampusMapStore.imageUrl;

  final ImageProvider? image;
  final OfficialCampusMapStore? store;

  @override
  State<OfficialCampusMapPage> createState() => _OfficialCampusMapPageState();
}

class _OfficialCampusMapPageState extends State<OfficialCampusMapPage> {
  int _attempt = 0;

  late final _store = widget.store ?? OfficialCampusMapStore.shared;
  @override
  void initState() {
    super.initState();
    if (widget.image == null) {
      _store.addListener(_mapChanged);
      unawaited(_store.refresh());
    }
  }

  void _mapChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.image == null) _store.removeListener(_mapChanged);
    super.dispose();
  }

  bool _sharing = false;
  Future<void> _shareArtwork() async {
    if (_sharing) return;
    _sharing = true;
    try {
      final path = await _store.localPath();
      if (!mounted) return;
      await saveOrSharePreview(
        context,
        path: path,
        title: 'campus-map.jpg',
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      if (mounted) BnbuToast.show(context, context.l10n.text('文件操作未完成，请重试。'));
    } finally {
      _sharing = false;
    }
  }

  Future<void> _retry() async {
    if (widget.image == null) {
      await _store.refresh(force: true);
    } else {
      await widget.image!.evict();
    }
    if (mounted) setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bnbuTheme.canvas,
      appBar: FilePreviewAppBar(
        title: context.l10n.text('官方校园地图'),
        onReload: _retry,
        onShare: _shareArtwork,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rotate = constraints.maxHeight > constraints.maxWidth;
            return InteractiveViewer(
              key: ValueKey('$_attempt-$rotate'),
              minScale: 1,
              maxScale: 8,
              child: Image(
                image:
                    widget.image ??
                    (_store.bytes == null
                        ? const AssetImage(OfficialCampusMapStore.bundledAsset)
                        : MemoryImage(_store.bytes!) as ImageProvider),
                gaplessPlayback: true,
                width: rotate ? constraints.maxHeight : constraints.maxWidth,
                height: rotate ? constraints.maxWidth : constraints.maxHeight,
                fit: BoxFit.contain,
                semanticLabel: context.l10n.text('官方校园地图'),
                frameBuilder: (context, child, frame, synchronous) =>
                    synchronous || frame != null
                    ? RotatedBox(quarterTurns: rotate ? 1 : 0, child: child)
                    : const Center(child: BnbuActivityIndicator()),
                errorBuilder: (context, error, stackTrace) => Center(
                  child: TextButton(
                    onPressed: _retry,
                    child: const BnbuText('内容暂不可用，重试'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
