import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/mail_sender_avatar_service.dart';
import '../theme/app_theme.dart';

/// A public teacher photo with bounded recovery after an unavailable load.
class TeacherPortrait extends StatefulWidget {
  const TeacherPortrait({
    super.key,
    required this.photoUrl,
    required this.size,
    this.cache,
  });
  final String photoUrl;
  final double size;
  final IoMailSenderAvatarService? cache;

  @override
  State<TeacherPortrait> createState() => _TeacherPortraitState();
}

class _TeacherPortraitState extends State<TeacherPortrait>
    with WidgetsBindingObserver {
  IoMailSenderAvatarService get _cache =>
      widget.cache ?? IoMailSenderAvatarService.sharedPortraitCache;
  Uint8List? _bytes;
  Timer? _retry;
  bool _loading = false;
  int _generation = 0;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cache.revision.addListener(_cacheChanged);
    unawaited(_load());
  }

  void _cacheChanged() {
    if (!_loading) unawaited(_load());
  }

  @override
  void didUpdateWidget(TeacherPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      (oldWidget.cache ?? IoMailSenderAvatarService.sharedPortraitCache)
          .revision
          .removeListener(_cacheChanged);
      _cache.revision.addListener(_cacheChanged);
    }
    if (oldWidget.photoUrl != widget.photoUrl ||
        oldWidget.size != widget.size ||
        oldWidget.cache != widget.cache) {
      _bytes = null;
      _retries = 0;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _bytes == null && !_loading) {
      _retryNow();
    }
  }

  void _retryNow() {
    _retries = 0;
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _retry?.cancel();
    _loading = true;
    Uint8List? bytes;
    try {
      bytes = await _cache.loadTeacherPortrait(
        widget.photoUrl,
        dimension: widget.size * 3 > 96 ? 320 : 96,
      );
    } on Object {
      // Cache/path failures are recoverable just like unavailable downloads.
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (bytes != null) _bytes = bytes;
    });
    if (bytes == null && widget.photoUrl.isNotEmpty && _retries < 2) {
      _retries++;
      _retry = Timer(Duration(seconds: _retries), () => unawaited(_load()));
    }
  }

  @override
  void dispose() {
    _generation++;
    _retry?.cancel();
    _cache.revision.removeListener(_cacheChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final fallback = ColoredBox(
      color: tokens.infoContainer,
      child: Center(
        child: Icon(
          LucideIcons.userRound300,
          size: widget.size * .42,
          color: tokens.info,
        ),
      ),
    );
    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: _bytes == null
            ? GestureDetector(
                onTap: !_loading && widget.photoUrl.isNotEmpty
                    ? _retryNow
                    : null,
                child: Semantics(
                  button: !_loading,
                  label: context.l10n.text('重试'),
                  child: fallback,
                ),
              )
            : Image.memory(
                _bytes!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
