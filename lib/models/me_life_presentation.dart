import 'package:flutter/painting.dart';
import 'landmark_review.dart';

class LifeStyle {
  LifeStyle.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      names = Map<String, String>.from(j['names'] as Map? ?? {}),
      template = j['template'] as String? ?? 'plain',
      foreground = parseColor(j['foreground'], const Color(0xff7d899f)),
      background = parseColor(j['background'], const Color(0x00ffffff)),
      border = parseColor(j['border'], const Color(0xffcbd0da)),
      detailAllowed =
          j['detail_allowed'] as bool? ??
          !['brand', 'flame'].contains(j['template']),
      accent = parseColor(j['accent'], const Color(0xffffe7ab));
  final String id, template;
  final bool detailAllowed;
  final Map<String, String> names;
  final Color foreground, background, border, accent;
  static final fallback = LifeStyle.fromJson({
    'id': 'fallback',
    'template': 'plain',
  });
  static Color parseColor(dynamic value, Color fallback) {
    if (value is! String ||
        !RegExp(r'^#[a-fA-F0-9]{6}([a-fA-F0-9]{2})?$').hasMatch(value)) {
      return fallback;
    }
    final rgb = int.parse(value.substring(1, 7), radix: 16);
    final alpha = value.length == 9
        ? int.parse(value.substring(7), radix: 16)
        : 255;
    return Color((alpha << 24) | rgb);
  }
}

class LifeTag {
  LifeTag.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      texts = Map<String, String>.from(j['texts'] as Map);
  final String id;
  final Map<String, String> texts;
}

class LifeTagBinding {
  LifeTagBinding.fromJson(Map<String, dynamic> j)
    : tagId = j['tag_id'] as String,
      styleId = j['style_id'] as String;
  final String tagId, styleId;
}

class LifeTagSlots {
  LifeTagSlots.fromJson(Map<String, dynamic> j)
    : topLeft = read(j['image_top_left']),
      bottomLeft = read(j['image_bottom_left']),
      scoreAfter = read(j['score_after']),
      below = List.unmodifiable(
        ((j['bottom'] ?? j['score_below']) as List? ?? []).map(
          (e) => LifeTagBinding.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      ),
      hidden = j['hidden'] as String? {
    if (below.length > 32) throw const FormatException('tag slots');
  }
  static LifeTagBinding? read(dynamic j) =>
      j is Map ? LifeTagBinding.fromJson(Map<String, dynamic>.from(j)) : null;
  final LifeTagBinding? topLeft, bottomLeft, scoreAfter;
  final List<LifeTagBinding> below;
  final String? hidden;
}

class LifeSpotlight {
  LifeSpotlight.fromJson(Map<String, dynamic> j)
    : modes = List<String>.from(j['modes'] as List? ?? ['review']),
      activityLimit = j.containsKey('activity_limit')
          ? j['activity_limit'] as int?
          : 3,
      reviewLimit = j.containsKey('review_limit')
          ? j['review_limit'] as int?
          : 3,
      activityStyle = j['activity_style_id'] as String? ?? 'rank-gold',
      reviewStyle = j['review_style_id'] as String? ?? 'flame-orange' {
    if (modes.toSet().length != modes.length ||
        modes.any((e) => !['activity', 'review', 'tag'].contains(e)) ||
        (modes.contains('tag') && modes.length > 1) ||
        (activityLimit != null && activityLimit! < 1) ||
        (reviewLimit != null && reviewLimit! < 1)) {
      throw const FormatException('spotlight');
    }
  }
  final List<String> modes;
  final int? activityLimit, reviewLimit;
  final String activityStyle, reviewStyle;
}

class LifeUnitPresentation {
  LifeUnitPresentation.fromJson(Map<String, dynamic> j)
    : policy = CommunityPolicy.fromJson(
        Map<String, dynamic>.from(j['policy'] as Map),
      ),
      score = (j['score'] as num?)?.toDouble(),
      ratingCount = j['rating_count'] as int? ?? 0,
      content = j['content'] is Map
          ? Map<String, dynamic>.from(j['content'] as Map)
          : null;
  final CommunityPolicy policy;
  final double? score;
  final int ratingCount;
  final Map<String, dynamic>? content;
}

/// One step per explicit refresh; finite source lists alternate without a timer.
T? lifeRotationItem<T>(List<T> activities, List<T> reviews, int cursor) {
  final sources = [
    if (activities.isNotEmpty) activities,
    if (reviews.isNotEmpty) reviews,
  ];
  if (sources.isEmpty) return null;
  final source = sources[cursor % sources.length];
  return source[(cursor ~/ sources.length) % source.length];
}

class LifeIconContent {
  LifeIconContent.fromJson(Map<String, dynamic> j)
    : icon = j['icon'] as String? ?? 'location',
      source = j['source'] as String? ?? 'location',
      texts = Map<String, String>.from(j['texts'] as Map? ?? {});
  final String icon, source;
  final Map<String, String> texts;
}

class LifeCommentTag {
  LifeCommentTag.fromJson(Map<String, dynamic> j)
    : texts = Map<String, String>.from(j['texts'] as Map? ?? {}),
      style = LifeStyle.fromJson(Map<String, dynamic>.from(j['style'] as Map));
  final Map<String, String> texts;
  final LifeStyle style;
}
