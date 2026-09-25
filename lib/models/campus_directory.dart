import 'dart:convert';

import 'package:crypto/crypto.dart';

enum CampusDirectoryCategory { college, researchInstitute, administration }

extension CampusDirectoryBrowseCategory on CampusDirectoryCategory {
  /// Institutes appear alongside colleges while source categories stay intact.
  CampusDirectoryCategory get browseCategory =>
      this == CampusDirectoryCategory.researchInstitute
      ? CampusDirectoryCategory.college
      : this;
}

class CampusDirectoryContact {
  const CampusDirectoryContact({
    required this.nameCn,
    required this.nameEn,
    required this.office,
    required this.phones,
    required this.emails,
    required this.responsibilities,
    this.kind = 'service',
    this.sourceUrls = const [],
    this.serviceHours = '',
  });

  factory CampusDirectoryContact.fromJson(Map<String, dynamic> json) {
    return CampusDirectoryContact(
      nameCn: _string(json['name_cn']),
      nameEn: _string(json['name_en']),
      office: _string(json['office']),
      phones: _strings(json['phones']),
      emails: _strings(json['emails']),
      responsibilities: _strings(json['responsibilities']),
      kind: _string(json['kind']),
      sourceUrls: _strings(json['source_urls']),
      serviceHours: _string(json['service_hours']),
    );
  }

  final String nameCn;
  final String nameEn;
  final String office;
  final List<String> phones;
  final List<String> emails;
  final List<String> responsibilities;
  final String kind;
  final List<String> sourceUrls;
  final String serviceHours;
}

class DirectorySyncInfo {
  const DirectorySyncInfo({
    this.version = '',
    this.lastSuccessAt,
    this.changedAt,
    this.status = 'unverified',
  });
  factory DirectorySyncInfo.fromJson(Map<String, dynamic> json) =>
      DirectorySyncInfo(
        version: _string(json['version']),
        lastSuccessAt: DateTime.tryParse(_string(json['last_success_at'])),
        changedAt: DateTime.tryParse(_string(json['changed_at'])),
        status: _string(json['status']),
      );
  final String version;
  final DateTime? lastSuccessAt;
  final DateTime? changedAt;
  final String status;
}

DirectorySyncInfo? _syncInfo(Object? json) => json is Map
    ? DirectorySyncInfo.fromJson(json.cast<String, dynamic>())
    : null;

class CampusDirectoryOrganization {
  const CampusDirectoryOrganization({
    required this.id,
    required this.category,
    required this.nameCn,
    required this.nameEn,
    required this.shortName,
    required this.websiteUrl,
    required this.facultyUrl,
    required this.teacherUnit,
    required this.office,
    required this.phones,
    required this.emails,
    required this.responsibilities,
    required this.contacts,
    required this.embeddedStaff,
    required this.sourceUrls,
    this.sync,
    this.services = const [],
    this.sources = const [],
  });

  factory CampusDirectoryOrganization.fromJson(Map<String, dynamic> json) {
    final category = switch (_string(json['category'])) {
      'college' => CampusDirectoryCategory.college,
      'research_institute' => CampusDirectoryCategory.researchInstitute,
      'administration' => CampusDirectoryCategory.administration,
      final value => throw FormatException('未知目录分类：$value'),
    };
    final contacts = json['contacts'];
    return CampusDirectoryOrganization(
      id: _string(json['id']),
      category: category,
      nameCn: _string(json['name_cn']),
      nameEn: _string(json['name_en']),
      shortName: _string(json['short_name']),
      websiteUrl: _string(json['website_url']),
      facultyUrl: _string(json['faculty_url']),
      teacherUnit: _string(json['teacher_unit']),
      office: _string(json['office']),
      phones: _strings(json['phones']),
      emails: _strings(json['emails']),
      responsibilities: _strings(json['responsibilities']),
      contacts: contacts is List
          ? contacts
                .whereType<Map>()
                .map(
                  (item) => CampusDirectoryContact.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const [],
      embeddedStaff: json['staff'] is List
          ? (json['staff'] as List)
                .whereType<Map>()
                .map(
                  (item) => OfficialTeacherProfile.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const [],
      sourceUrls: _strings(json['source_urls']),
      sync: _syncInfo(json['sync']),
      services: _objects(json['services'], CampusDirectoryContact.fromJson),
      sources: json['sources'] is List
          ? (json['sources'] as List)
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
          : const [],
    );
  }

  final String id;
  final CampusDirectoryCategory category;
  final String nameCn;
  final String nameEn;
  final String shortName;
  final String websiteUrl;
  final String facultyUrl;
  final String teacherUnit;
  final String office;
  final List<String> phones;
  final List<String> emails;
  final List<String> responsibilities;
  final List<CampusDirectoryContact> contacts;
  final List<OfficialTeacherProfile> embeddedStaff;
  final List<String> sourceUrls;
  final DirectorySyncInfo? sync;
  final List<CampusDirectoryContact> services;
  final List<Map<String, dynamic>> sources;
}

enum OfficialTeacherMatchType { exact, candidate }

class OfficialTeacherLink {
  const OfficialTeacherLink({required this.name, required this.url});

  factory OfficialTeacherLink.fromJson(Map<String, dynamic> json) {
    return OfficialTeacherLink(
      name: _string(json['name']),
      url: _string(json['url']),
    );
  }

  final String name;
  final String url;
}

class OfficialTeacherSectionItem {
  const OfficialTeacherSectionItem({
    required this.title,
    required this.content,
    required this.link,
  });

  factory OfficialTeacherSectionItem.fromJson(Map<String, dynamic> json) {
    return OfficialTeacherSectionItem(
      title: _string(json['title']),
      content: _string(json['content']),
      link: _string(json['link']),
    );
  }

  final String title;
  final String content;
  final String link;
}

class OfficialTeacherSection {
  const OfficialTeacherSection({
    required this.name,
    required this.type,
    required this.items,
  });

  factory OfficialTeacherSection.fromJson(Map<String, dynamic> json) {
    return OfficialTeacherSection(
      name: _string(json['name']),
      type: _string(json['type']),
      items: _objects(json['items'], OfficialTeacherSectionItem.fromJson),
    );
  }

  final String name;
  final String type;
  final List<OfficialTeacherSectionItem> items;
}

class OfficialTeacherProfile {
  const OfficialTeacherProfile({
    required this.name,
    required this.nameEn,
    required this.email,
    required this.title,
    required this.titleEn,
    required this.position,
    required this.office,
    required this.telephone,
    required this.academicCn,
    required this.academicEn,
    required this.educationCn,
    required this.educationEn,
    required this.unitNames,
    this.primaryAppointments = const [],
    this.crossAppointments = const [],
    required this.photoUrl,
    required this.profileUrl,
    this.timetable,
    this.profileLinks = const [],
    this.sections = const [],
    required this.sourceUpdatedAt,
    this.matchType = OfficialTeacherMatchType.candidate,
    String reviewKey = '',
    this.personKind = 'teacher',
    this.contactEmails = const [],
    this.responsibilities = const [],
    this.serviceGroup = '',
    this.sourceUrls = const [],
  }) : _reviewKey = reviewKey;

  factory OfficialTeacherProfile.fromJson(Map<String, dynamic> json) {
    return OfficialTeacherProfile(
      name: _string(json['name']),
      personKind: _string(json['person_kind']).isEmpty
          ? 'teacher'
          : _string(json['person_kind']),
      contactEmails: _strings(json['contact_emails']),
      responsibilities: _strings(json['responsibilities']),
      serviceGroup: _string(json['service_group']),
      sourceUrls: _strings(json['source_urls']),
      nameEn: _string(json['name_en']),
      email: _string(json['email']),
      title: _string(json['title']),
      titleEn: _string(json['title_en']),
      position: _string(json['position']),
      office: _string(json['office']),
      telephone: _string(json['telephone']),
      academicCn: _string(json['academic_cn']),
      academicEn: _string(json['academic_en']),
      educationCn: _string(json['education_cn']),
      educationEn: _string(json['education_en']),
      unitNames: _strings(json['unit_names']),
      primaryAppointments: _objects(
        json['primary_appointments'],
        OfficialTeacherLink.fromJson,
      ),
      crossAppointments: _objects(
        json['cross_appointments'],
        OfficialTeacherLink.fromJson,
      ),
      photoUrl: _string(json['photo_url']),
      profileUrl: _string(json['profile_url']),
      timetable: json['timetable'] is Map
          ? OfficialTeacherLink.fromJson(
              (json['timetable'] as Map).cast<String, dynamic>(),
            )
          : null,
      profileLinks: _objects(
        json['profile_links'],
        OfficialTeacherLink.fromJson,
      ),
      sections: _objects(json['sections'], OfficialTeacherSection.fromJson),
      sourceUpdatedAt: DateTime.tryParse(_string(json['source_updated_at'])),
      reviewKey: _string(json['review_key']),
      matchType: _string(json['match_type']) == 'exact'
          ? OfficialTeacherMatchType.exact
          : OfficialTeacherMatchType.candidate,
    );
  }

  final String name;
  final String personKind;
  final List<String> contactEmails;
  final List<String> responsibilities;
  final String serviceGroup;
  final List<String> sourceUrls;
  final String nameEn;
  final String email;
  final String title;
  final String titleEn;
  final String position;
  final String office;
  final String telephone;
  final String academicCn;
  final String academicEn;
  final String educationCn;
  final String educationEn;
  final List<String> unitNames;
  final List<OfficialTeacherLink> primaryAppointments;
  final List<OfficialTeacherLink> crossAppointments;
  final String photoUrl;
  final String profileUrl;
  final OfficialTeacherLink? timetable;
  final List<OfficialTeacherLink> profileLinks;
  final List<OfficialTeacherSection> sections;
  final DateTime? sourceUpdatedAt;
  final OfficialTeacherMatchType matchType;
  final String _reviewKey;

  String get reviewKey => _reviewKey.isNotEmpty
      ? _reviewKey
      : buildTeacherReviewKey(
          profileUrl: profileUrl,
          email: email,
          name: name,
          nameEn: nameEn,
          unitNames: unitNames,
        );

  String get displayName => name.isNotEmpty ? name : nameEn;

  String get displayTitle {
    return [position, title].where((value) => value.isNotEmpty).join(' · ');
  }
}

String buildTeacherReviewKey({
  String profileUrl = '',
  String email = '',
  String name = '',
  String nameEn = '',
  Iterable<String> unitNames = const [],
}) {
  final normalizedProfile = profileUrl.trim().toLowerCase();
  final normalizedEmail = email.trim().toLowerCase();
  final String source;
  if (normalizedProfile.isNotEmpty) {
    source = 'profile|$normalizedProfile';
  } else if (normalizedEmail.isNotEmpty) {
    source = 'email|$normalizedEmail';
  } else {
    final units =
        unitNames
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    source =
        'name|${name.trim().toLowerCase()}|'
        '${nameEn.trim().toLowerCase()}|${units.join(',')}';
  }
  final digest = sha256.convert(utf8.encode(source)).toString();
  return 'tchr_${digest.substring(0, 40)}';
}

class OfficialTeacherPage {
  const OfficialTeacherPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.units,
    this.sync,
  });

  factory OfficialTeacherPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return OfficialTeacherPage(
      items: items is List
          ? items
                .whereType<Map>()
                .map(
                  (item) => OfficialTeacherProfile.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const [],
      total: json['total'] is int ? json['total'] as int : 0,
      offset: json['offset'] is int ? json['offset'] as int : 0,
      limit: json['limit'] is int ? json['limit'] as int : 0,
      units: _strings(json['units']),
      sync: _syncInfo(json['sync']),
    );
  }

  final List<OfficialTeacherProfile> items;
  final int total;
  final int offset;
  final int limit;
  final List<String> units;
  final DirectorySyncInfo? sync;
}

String _string(Object? value) => value is String ? value.trim() : '';

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<T> _objects<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => fromJson(item.cast<String, dynamic>()))
      .toList(growable: false);
}
