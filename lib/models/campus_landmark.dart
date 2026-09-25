import 'package:flutter/widgets.dart';

import '../l10n/bnbu_localizations.dart';
import 'me_life_presentation.dart';

typedef LandmarkTranslations = Map<String, String>;

String landmarkText(
  LandmarkTranslations values,
  BuildContext context,
  String fallback,
) {
  final l10n = BnbuLocalizations.of(context);
  final language = l10n.isEnglish
      ? 'en'
      : l10n.isTraditionalChinese
      ? 'zh-Hant'
      : 'zh-Hans';
  return values[language]?.trim().isNotEmpty == true
      ? values[language]!
      : values[fallback] ?? '';
}

Map<String, String> _texts(dynamic value) {
  if (value is! Map) throw const FormatException('translations');
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (!['zh-Hans', 'zh-Hant', 'en'].contains(entry.key) ||
        entry.value is! String ||
        (entry.value as String).length > 12000) {
      throw const FormatException('translation');
    }
    result[entry.key as String] = entry.value as String;
  }
  return Map.unmodifiable(result);
}

String _id(dynamic value) {
  if (value is! String ||
      !RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(value)) {
    throw const FormatException('id');
  }
  return value;
}

class LandmarkEvidenceSource {
  LandmarkEvidenceSource.fromJson(Map<String, dynamic> j)
    : id = _id(j['id']),
      title = _texts(j['title']),
      url = j['url'] as String,
      publisher = _texts(j['publisher'] ?? {}),
      recordId = j['record_id'] as String?,
      checkedOn = j['checked_on'] as String?,
      note = _texts(j['note'] ?? {}) {
    final uri = Uri.tryParse(url);
    if (url.length > 2000 ||
        uri?.scheme != 'https' ||
        uri!.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        url.trim() != url ||
        RegExp(r'[\x00-\x1f]').hasMatch(url) ||
        title.values.any((v) => v.length > 120) ||
        publisher.values.any((v) => v.length > 120) ||
        note.values.any((v) => v.length > 500) ||
        (recordId?.length ?? 0) > 128 ||
        (checkedOn != null &&
            (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(checkedOn!) ||
                DateTime.tryParse(
                      checkedOn!,
                    )?.toIso8601String().substring(0, 10) !=
                    checkedOn))) {
      throw const FormatException('evidence source');
    }
  }
  final String id, url;
  final String? recordId, checkedOn;
  final LandmarkTranslations title, publisher, note;
}

class LandmarkFact {
  LandmarkFact.fromJson(Map<String, dynamic> j)
    : id = _id(j['id']),
      label = _texts(j['label']),
      value = _texts(j['value']),
      period = j['period'] as String?,
      sourceIds = List.unmodifiable((j['source_ids'] as List).map(_id)) {
    if (label.values.any((v) => v.length > 120) ||
        value.values.any((v) => v.length > 500) ||
        (period?.length ?? 0) > 80 ||
        sourceIds.isEmpty ||
        sourceIds.length > 12 ||
        sourceIds.toSet().length != sourceIds.length) {
      throw const FormatException('landmark fact');
    }
  }
  final String id;
  final String? period;
  final LandmarkTranslations label, value;
  final List<String> sourceIds;
}

class LandmarkPhoto {
  LandmarkPhoto.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      source = json['source'] as String? ?? '',
      author = json['author'] as String? ?? '',
      sourceUrl = json['source_url'] as String? ?? '',
      license = json['license'] as String? ?? '',
      note = _texts(json['note'] ?? {}),
      focusX = (json['focus_x'] as num).toDouble(),
      focusY = (json['focus_y'] as num).toDouble() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !focusX.isFinite ||
        !focusY.isFinite ||
        focusX < 0 ||
        focusX > 1 ||
        focusY < 0 ||
        focusY > 1) {
      throw const FormatException('photo');
    }
    final uri = Uri.tryParse(sourceUrl);
    if (source.length > 300 ||
        author.length > 200 ||
        license.length > 200 ||
        sourceUrl.length > 2000 ||
        (sourceUrl.isNotEmpty &&
            (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty))) {
      throw const FormatException('photo source');
    }
  }
  final String id;
  final String source, author, sourceUrl, license;
  final LandmarkTranslations note;
  final double focusX, focusY;
  Alignment get alignment => Alignment(focusX * 2 - 1, focusY * 2 - 1);
}

class LandmarkCategory {
  LandmarkCategory.fromJson(Map<String, dynamic> json)
    : id = _id(json['id']),
      parentId = json['parent_id'] == null ? null : _id(json['parent_id']),
      names = _texts(json['names']),
      iconBefore = json['icon_before'] is Map
          ? LandmarkPhoto.fromJson(
              Map<String, dynamic>.from(json['icon_before'] as Map),
            )
          : null,
      iconAfter = json['icon_after'] is Map
          ? LandmarkPhoto.fromJson(
              Map<String, dynamic>.from(json['icon_after'] as Map),
            )
          : null;
  final String id;
  final String? parentId;
  final LandmarkPhoto? iconBefore, iconAfter;
  final LandmarkTranslations names;
}

class CampusLandmark {
  CampusLandmark.fromJson(Map<String, dynamic> json)
    : avatar = json['avatar'] is Map
          ? LandmarkPhoto.fromJson(
              Map<String, dynamic>.from(json['avatar'] as Map),
            )
          : null,
      avatarRatio = json['avatar_ratio'] == '4:3' ? 4 / 3 : 1,
      ratingEnabled = json['rating_enabled'] != false,
      iconRow = List.unmodifiable(
        ((json['icon_row'] as List?) ??
                const [
                  {'icon': 'location', 'source': 'location'},
                ])
            .map(
              (e) =>
                  LifeIconContent.fromJson(Map<String, dynamic>.from(e as Map)),
            ),
      ),
      listImageRatio = json['list_image_ratio'] == '4:3' ? 4 / 3 : 1,
      tagSlots = LifeTagSlots.fromJson(
        Map<String, dynamic>.from(json['tag_slots'] as Map? ?? {}),
      ),
      spotlight = LifeSpotlight.fromJson(
        Map<String, dynamic>.from(json['spotlight'] as Map? ?? {}),
      ),
      openingHours = _texts(json['opening_hours'] ?? {}),
      tags = List<String>.from(json['tags'] as List? ?? const []),
      cover = json['cover'] is Map
          ? LandmarkPhoto.fromJson(
              Map<String, dynamic>.from(json['cover'] as Map),
            )
          : (!json.containsKey('cover') && (json['photos'] as List).isNotEmpty
                ? LandmarkPhoto.fromJson(
                    Map<String, dynamic>.from(json['photos'][0] as Map),
                  )
                : null),
      id = _id(json['id']),
      categoryId = _id(json['category_id']),
      names = _texts(json['names']),
      descriptions = _texts(json['descriptions']),
      aliases = List.unmodifiable(
        List<String>.from(json['aliases'] as List? ?? []),
      ),
      sources = List.unmodifiable(
        (json['sources'] as List? ?? []).map(
          (v) => LandmarkEvidenceSource.fromJson(
            Map<String, dynamic>.from(v as Map),
          ),
        ),
      ),
      facts = List.unmodifiable(
        (json['facts'] as List? ?? []).map(
          (v) => LandmarkFact.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      locations = _texts(json['locations']),
      photos = List.unmodifiable(
        (json['photos'] as List).map(
          (p) => LandmarkPhoto.fromJson(Map<String, dynamic>.from(p as Map)),
        ),
      ),
      longitude = (json['position']?['longitude'] as num?)?.toDouble(),
      latitude = (json['position']?['latitude'] as num?)?.toDouble() {
    if (aliases.length > 16 ||
        aliases.any((v) => v.trim().isEmpty || v.length > 120) ||
        sources.length > 12 ||
        facts.length > 16 ||
        sources.map((s) => s.id).toSet().length != sources.length ||
        facts.map((f) => f.id).toSet().length != facts.length ||
        facts.any(
          (f) => f.sourceIds.any((id) => !sources.any((s) => s.id == id)),
        )) {
      throw const FormatException('landmark evidence');
    }
    if (cover != null && !photos.any((p) => p.id == cover!.id)) {
      throw const FormatException('cover');
    }
    if (photos.length > 12 || (longitude == null) != (latitude == null)) {
      throw const FormatException('landmark');
    }
    if (longitude != null &&
        (!longitude!.isFinite ||
            !latitude!.isFinite ||
            longitude! < -180 ||
            longitude! > 180 ||
            latitude! < -90 ||
            latitude! > 90 ||
            json['position']['coordinate_system'] != 'GCJ-02')) {
      throw const FormatException('position');
    }
  }
  final String id, categoryId;
  final LandmarkTranslations names, descriptions, locations;
  final List<String> aliases;
  final List<LandmarkEvidenceSource> sources;
  final List<LandmarkFact> facts;
  final List<LandmarkPhoto> photos;
  final LandmarkPhoto? cover, avatar;
  final double avatarRatio, listImageRatio;
  final bool ratingEnabled;
  final List<LifeIconContent> iconRow;
  final LifeTagSlots tagSlots;
  final LifeSpotlight spotlight;
  final LandmarkTranslations openingHours;
  final List<String> tags;
  final double? longitude, latitude;
}

class LandmarkCatalog {
  LandmarkCatalog.fromJson(this.json)
    : version = json['version'] as int,
      defaultLanguage = json['catalog']['default_language'] as String,
      title = _texts(json['catalog']['title']),
      styles = List.unmodifiable(
        (json['catalog']['styles'] as List? ?? []).map(
          (e) => LifeStyle.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      ),
      tagDefinitions = List.unmodifiable(
        (json['catalog']['tag_definitions'] as List? ?? []).map(
          (e) => LifeTag.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      ),
      headerOpacity =
          (json['catalog']['header']?['opacity'] as num?)?.toDouble() ?? .3,
      headerBackground = json['catalog']['header']?['background'] is Map
          ? LandmarkPhoto.fromJson(
              Map<String, dynamic>.from(
                json['catalog']['header']['background'] as Map,
              ),
            )
          : null,
      categories = List.unmodifiable(
        (json['catalog']['categories'] as List).map(
          (v) => LandmarkCategory.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      landmarks = List.unmodifiable(
        (json['catalog']['landmarks'] as List).map(
          (v) => CampusLandmark.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ) {
    if (!headerOpacity.isFinite ||
        headerOpacity < 0 ||
        headerOpacity > 1 ||
        json['schema_version'] != 1 ||
        version < 0 ||
        !['zh-Hans', 'zh-Hant', 'en'].contains(defaultLanguage) ||
        categories.length > 100 ||
        landmarks.length > 1000) {
      throw const FormatException('catalog');
    }
    final ids = categories.map((c) => c.id).toSet();
    if (ids.length != categories.length ||
        landmarks.map((i) => i.id).toSet().length != landmarks.length ||
        landmarks.any((i) => !ids.contains(i.categoryId))) {
      throw const FormatException('references');
    }
    for (final item in landmarks) {
      if (item.sources.any(
            (s) => (s.title[defaultLanguage] ?? '').trim().isEmpty,
          ) ||
          item.facts.any(
            (f) =>
                (f.label[defaultLanguage] ?? '').trim().isEmpty ||
                (f.value[defaultLanguage] ?? '').trim().isEmpty,
          )) {
        throw const FormatException('evidence language');
      }
    }
    for (final c in categories) {
      if (c.parentId != null &&
          !categories.any(
            (p) => p.id == c.parentId && p.parentId == null && p.id != c.id,
          )) {
        throw const FormatException('category');
      }
    }
  }
  final Map<String, dynamic> json;
  final int version;
  final String defaultLanguage;
  final LandmarkTranslations title;
  final List<LandmarkCategory> categories;
  final List<CampusLandmark> landmarks;
  final List<LifeStyle> styles;
  final List<LifeTag> tagDefinitions;
  final LandmarkPhoto? headerBackground;
  final double headerOpacity;
  LifeStyle style(String id) =>
      styles.where((s) => s.id == id).firstOrNull ?? LifeStyle.fallback;
  LifeTag? tag(String id) =>
      tagDefinitions.where((t) => t.id == id).firstOrNull;
}
