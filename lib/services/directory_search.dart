import 'package:lpinyin/lpinyin.dart';

import '../models/campus_directory.dart';

/// Shared fuzzy matching for the official directory and mail recipients.
///
/// Ordinary fields gain normalized and pinyin aliases. Person names also gain
/// Western/Chinese order aliases, so both `xiaodongxu` and `xuxiaodong` match
/// the same public profile without changing the displayed official name.
final class DirectorySearch {
  DirectorySearch._();

  static const int noMatch = 1000;
  static const Set<String> _ignoredNameTitles = {
    'dr',
    'mr',
    'mrs',
    'ms',
    'prof',
    'professor',
  };

  static final Map<String, Set<String>> _fieldAliasCache = {};
  static final Map<String, Set<String>> _nameAliasCache = {};

  static bool matchesOrganization(
    CampusDirectoryOrganization organization,
    String query,
  ) {
    return scoreOrganization(organization, query) < noMatch;
  }

  static int scoreOrganization(
    CampusDirectoryOrganization organization,
    String query,
  ) {
    final values = <String>[
      organization.nameCn,
      organization.nameEn,
      organization.shortName,
      organization.teacherUnit,
      organization.office,
      ...organization.phones,
      ...organization.emails,
      ...organization.responsibilities,
    ];
    final personNames = <String>[];
    for (final contact in [
      ...organization.contacts,
      ...organization.services,
    ]) {
      values.addAll([
        contact.nameCn,
        contact.nameEn,
        contact.office,
        contact.serviceHours,
        ...contact.phones,
        ...contact.emails,
        ...contact.responsibilities,
      ]);
      personNames.addAll([contact.nameCn, contact.nameEn]);
    }
    for (final staff in organization.embeddedStaff) {
      values.addAll(_teacherValues(staff));
      personNames.addAll([staff.name, staff.nameEn]);
    }
    return score(query, values: values, personNames: personNames);
  }

  static int scoreTeacher(OfficialTeacherProfile teacher, String query) {
    return score(
      query,
      values: _teacherValues(teacher),
      personNames: [teacher.name, teacher.nameEn],
    );
  }

  static bool teacherBelongsToOrganization(
    OfficialTeacherProfile teacher,
    CampusDirectoryOrganization organization,
  ) {
    final teacherUnits = teacher.unitNames
        .map((value) => _normalize(value.toLowerCase()))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (teacherUnits.isEmpty) return false;
    final organizationUnits = <String>{
      organization.nameCn,
      organization.nameEn,
      organization.teacherUnit,
      for (final contact in organization.contacts) ...[
        contact.nameCn,
        contact.nameEn,
      ],
    }.map((value) => _normalize(value.toLowerCase()));
    return organizationUnits.any(teacherUnits.contains);
  }

  static bool isExactTeacherName(OfficialTeacherProfile teacher, String query) {
    return [
      teacher.name,
      teacher.nameEn,
    ].any((name) => isExactPersonName(name, query));
  }

  static bool isExactOrganizationName(
    CampusDirectoryOrganization organization,
    String query,
  ) {
    final wanted = _normalize(query.toLowerCase());
    if (wanted.isEmpty) return false;
    return [
      organization.nameCn,
      organization.nameEn,
      organization.shortName,
    ].any((value) => _normalize(value.toLowerCase()) == wanted);
  }

  static int score(
    String query, {
    required Iterable<String> values,
    Iterable<String> personNames = const [],
  }) {
    final fields = [...values, ...personNames];
    final addressQuery = query.trim().toLowerCase();
    if (addressQuery.contains('@')) {
      // Email punctuation is identity, and the domain is never a name token.
      return fields.any((value) => value.trim().toLowerCase() == addressQuery)
          ? 0
          : noMatch;
    }
    final queryAliases = _exactPersonAliases(query);
    if (queryAliases.isEmpty) return 0;
    final candidateAliases = <String>{};
    for (final value in values) {
      candidateAliases.addAll(_aliases(value, personName: false));
    }
    for (final name in personNames) {
      candidateAliases.addAll(_aliases(name, personName: true));
    }
    var best = noMatch;
    for (final wanted in queryAliases) {
      for (final candidate in candidateAliases) {
        final current = _aliasScore(candidate, wanted);
        if (current < best) best = current;
      }
    }
    // Multiple search terms must all match, even across name and department.
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => !_ignoredNameTitles.contains(_normalize(term)))
        .toList();
    if (terms.length > 1) {
      var worst = 0;
      for (final term in terms) {
        var termBest = noMatch;
        for (final wanted in _exactPersonAliases(term)) {
          for (final candidate in candidateAliases) {
            final score = wanted.length < 3
                ? (candidate == wanted ? 0 : noMatch)
                : _aliasScore(candidate, wanted);
            if (score < termBest) termBest = score;
          }
        }
        if (termBest >= noMatch) return best;
        if (termBest > worst) worst = termBest;
      }
      if (12 + worst < best) best = 12 + worst;
    }
    return best;
  }

  static bool isExactPersonName(String name, String query) {
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(query)) {
      return _normalize(name) == _normalize(query);
    }
    final wanted = _exactPersonAliases(query);
    return _exactPersonAliases(name).any(wanted.contains);
  }

  static Set<String> _aliases(String value, {required bool personName}) {
    final normalizedValue = value.trim().toLowerCase();
    if (normalizedValue.isEmpty) return const {};
    if (normalizedValue.contains('@')) {
      return {normalizedValue, normalizedValue.split('@').first};
    }
    final cache = personName ? _nameAliasCache : _fieldAliasCache;
    final cached = cache[normalizedValue];
    if (cached != null) return cached;

    final aliases = <String>{};
    final normalized = _normalize(normalizedValue);
    if (normalized.isNotEmpty) aliases.add(normalized);

    final latinTokens = RegExp(r'[a-z0-9]+')
        .allMatches(normalizedValue)
        .map((match) => match.group(0)!)
        .where((token) => !_ignoredNameTitles.contains(token))
        .toList(growable: false);
    if (latinTokens.isNotEmpty) {
      aliases.add(latinTokens.join());
      aliases.addAll(latinTokens);
      if (personName && latinTokens.length > 1) {
        aliases.add(latinTokens.reversed.join());
        _addRotations(aliases, latinTokens);
      }
    }

    if (RegExp(r'[\u3400-\u9fff]').hasMatch(normalizedValue)) {
      final pinyin = PinyinHelper.getPinyinE(
        normalizedValue,
        separator: ' ',
        defPinyin: '',
        format: PinyinFormat.WITHOUT_TONE,
      );
      final syllables = RegExp(r'[a-z0-9]+')
          .allMatches(pinyin.toLowerCase())
          .map((match) => match.group(0)!)
          .toList(growable: false);
      if (syllables.isNotEmpty) {
        aliases.add(syllables.join());
        aliases.addAll(syllables);
        aliases.add(syllables.map((item) => item[0]).join());
        if (personName && syllables.length > 1) {
          _addRotations(aliases, syllables);
        }
      }
    }

    if (cache.length >= 2048) cache.clear();
    final frozen = Set<String>.unmodifiable(
      aliases.where((item) => item.isNotEmpty),
    );
    cache[normalizedValue] = frozen;
    return frozen;
  }

  static void _addRotations(Set<String> aliases, List<String> tokens) {
    for (var shift = 1; shift < tokens.length; shift++) {
      aliases.add([...tokens.skip(shift), ...tokens.take(shift)].join());
    }
  }

  static int _aliasScore(String candidate, String query) {
    if (candidate == query) return 0;
    if (candidate.startsWith(query)) return 4;
    if (candidate.contains(query)) return 8;
    if (query.length >= 4 && _isWithinOneEdit(candidate, query)) return 16;
    return noMatch;
  }

  static bool _isWithinOneEdit(String left, String right) {
    if ((left.length - right.length).abs() > 1) return false;
    var leftIndex = 0;
    var rightIndex = 0;
    var edits = 0;
    while (leftIndex < left.length && rightIndex < right.length) {
      if (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex)) {
        leftIndex++;
        rightIndex++;
        continue;
      }
      edits++;
      if (edits > 1) return false;
      if (left.length > right.length) {
        leftIndex++;
      } else if (right.length > left.length) {
        rightIndex++;
      } else {
        leftIndex++;
        rightIndex++;
      }
    }
    if (leftIndex < left.length || rightIndex < right.length) edits++;
    return edits <= 1;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u3400-\u9fff]+'),
      '',
    );
  }

  static List<String> _teacherValues(OfficialTeacherProfile teacher) {
    return [
      teacher.name,
      teacher.nameEn,
      teacher.email,
      ...teacher.contactEmails,
      ...teacher.responsibilities,
      teacher.serviceGroup,
      teacher.title,
      teacher.titleEn,
      teacher.position,
      teacher.office,
      teacher.telephone,
      teacher.academicCn,
      teacher.academicEn,
      teacher.educationCn,
      teacher.educationEn,
      ...teacher.primaryAppointments.map((item) => item.name),
      ...teacher.crossAppointments.map((item) => item.name),
      ...teacher.profileLinks.map((item) => item.name),
      if (teacher.timetable case final timetable?) timetable.name,
      for (final section in teacher.sections) ...[
        section.name,
        for (final item in section.items) ...[item.title, item.content],
      ],
      ...teacher.unitNames,
    ];
  }

  static Set<String> _exactPersonAliases(String value) {
    final normalizedValue = value.trim().toLowerCase();
    if (normalizedValue.isEmpty) return const {};
    final aliases = <String>{_normalize(normalizedValue)};
    final latinTokens = RegExp(r'[a-z0-9]+')
        .allMatches(normalizedValue)
        .map((match) => match.group(0)!)
        .where((token) => !_ignoredNameTitles.contains(token))
        .toList(growable: false);
    if (latinTokens.isNotEmpty) {
      aliases.add(latinTokens.join());
      if (latinTokens.length > 1) _addRotations(aliases, latinTokens);
    }
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(normalizedValue)) {
      final pinyin = PinyinHelper.getPinyinE(
        normalizedValue,
        separator: ' ',
        defPinyin: '',
        format: PinyinFormat.WITHOUT_TONE,
      );
      final syllables = RegExp(r'[a-z0-9]+')
          .allMatches(pinyin.toLowerCase())
          .map((match) => match.group(0)!)
          .toList(growable: false);
      if (syllables.isNotEmpty) {
        aliases.add(syllables.join());
        if (syllables.length > 1) _addRotations(aliases, syllables);
      }
    }
    return aliases;
  }
}
