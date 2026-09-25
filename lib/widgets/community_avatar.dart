import 'package:dicebear_core/dicebear_core.dart' as dicebear;
import 'package:dicebear_styles/glyphs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config/app_config.dart';
import '../services/landmark_review_service.dart';

/// One pinned avatar style across settings, conversations and exported posters.
class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    required this.seed,
    this.url,
    this.size = 40,
  });
  final String seed;
  final String? url;
  final double size;
  static final _style = dicebear.Style.parse(glyphs);
  static final _cache = <String, String>{};

  static String svgForSeed(String seed) {
    final cached = _cache.remove(seed);
    if (cached != null) {
      _cache[seed] = cached;
      return cached;
    }
    final svg = dicebear.Avatar(_style, {'seed': seed, 'size': 128}).svg;
    if (_cache.length >= 128) _cache.remove(_cache.keys.first);
    return _cache[seed] = svg;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = SvgPicture.string(
      svgForSeed(seed),
      width: size,
      height: size,
    );
    final uri = url == null ? null : Uri.tryParse(url!);
    final safe =
        uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        RegExp(r'^/v2/community/avatars/[a-f0-9-]{36}$').hasMatch(uri.path) &&
        (!uri.hasQuery ||
            (uri.queryParameters.length == 1 &&
                RegExp(r'^[0-9]+$').hasMatch(uri.queryParameters['v'] ?? '')));
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: safe
            ? Image.network(
                '${AppConfig.syncServiceBaseUrl}$url',
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => fallback,
              )
            : fallback,
      ),
    );
  }
}

/// Uses an existing community identity only; viewing settings never enrolls it.
/// Before enrollment a random local portrait is retained per account, then the
/// server's public seed is cached for offline use once that identity exists.
class AccountCommunityAvatar extends StatefulWidget {
  const AccountCommunityAvatar({
    super.key,
    required this.username,
    this.size = 40,
  });
  final String username;
  final double size;
  @override
  State<AccountCommunityAvatar> createState() => _AccountCommunityAvatarState();
}

class _AccountCommunityAvatarState extends State<AccountCommunityAvatar> {
  String? seed;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(AccountCommunityAvatar old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username) {
      seed = null;
      load();
    }
  }

  Future<void> load() async {
    final current = ++generation;
    final username = widget.username;
    final store = CommunityAvatarSeedStore();
    try {
      final value = await store.local(username);
      if (mounted && current == generation) setState(() => seed = value);
      final remote = await store.refresh(username);
      if (mounted && current == generation && remote != null) {
        setState(() => seed = remote);
      }
    } catch (_) {
      // Retain the cached portrait when identity refresh is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) => seed == null
      ? SizedBox.square(dimension: widget.size)
      : CommunityAvatar(seed: seed!, size: widget.size);
}
