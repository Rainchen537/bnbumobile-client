import '../models/campus_directory.dart';
import 'campus_directory_service.dart';
import 'campus_contact_index.dart';
import 'directory_search.dart';

enum MailRecipientKind { person, organization }

class MailRecipientSuggestion {
  const MailRecipientSuggestion({
    required this.email,
    required this.displayName,
    required this.contextLabel,
    required this.kind,
    required this.searchValues,
    this.personNames = const [],
  });

  final String email;
  final String displayName;
  final String contextLabel;
  final MailRecipientKind kind;
  final List<String> searchValues;
  final List<String> personNames;
}

class MailRecipientDirectory {
  MailRecipientDirectory({CampusDirectoryService? directoryService})
    : _directoryService = directoryService ?? RemoteCampusDirectoryService(),
      _ownsDirectoryService = directoryService == null,
      _index = directoryService == null ? CampusContactIndex.shared : null;

  final CampusDirectoryService _directoryService;
  final bool _ownsDirectoryService;
  final CampusContactIndex? _index;

  Future<List<MailRecipientSuggestion>> searchLocal(String query) async {
    await _index?.loadLocal();
    final organizations = await _loadOrganizationSuggestions();
    return _rank(query, [
      ...organizations,
      for (final teacher in _index?.teachers ?? <OfficialTeacherProfile>[])
        _teacherSuggestion(
          teacher,
          fallbackContext: teacher.unitNames.join(' · '),
        ),
    ]);
  }

  Future<List<MailRecipientSuggestion>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final index = _index;
    if (index != null) {
      // One shared refresh, never a paginated biography query per keystroke.
      await index.refresh();
      return searchLocal(query);
    }
    final local = await searchLocal(query);
    final remote = query.trim().length >= 2
        ? await _directoryService.loadTeachers(query: query.trim(), limit: 100)
        : null;
    return _rank(query, [
      ...local,
      for (final teacher in remote?.items ?? <OfficialTeacherProfile>[])
        _teacherSuggestion(
          teacher,
          fallbackContext: teacher.unitNames.join(' · '),
        ),
    ]);
  }

  static List<MailRecipientSuggestion> _rank(
    String query,
    Iterable<MailRecipientSuggestion> candidates,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const [];
    var matches = candidates
        .where((item) => _score(item, normalizedQuery) < 90)
        .toList();
    final exactAddress = matches
        .where((item) => item.email.trim().toLowerCase() == normalizedQuery)
        .toList();
    final exactName = matches
        .where(
          (item) => [
            ...item.personNames,
            item.displayName,
          ].any((name) => DirectorySearch.isExactPersonName(name, query)),
        )
        .toList();
    if (exactAddress.isNotEmpty) {
      matches = exactAddress;
    } else if (exactName.isNotEmpty) {
      matches = exactName;
    }
    final byEmail = <String, MailRecipientSuggestion>{};
    for (final suggestion in matches) {
      final email = suggestion.email.trim().toLowerCase();
      if (!_looksLikeEmail(email)) continue;
      final existing = byEmail[email];
      if (existing == null ||
          (existing.kind == MailRecipientKind.organization &&
              suggestion.kind == MailRecipientKind.person)) {
        byEmail[email] = suggestion;
      }
    }

    final ranked = byEmail.values.toList(growable: false)
      ..sort((left, right) {
        final leftScore = _score(left, normalizedQuery);
        final rightScore = _score(right, normalizedQuery);
        if (leftScore != rightScore) return leftScore.compareTo(rightScore);
        final kindOrder = left.kind.index.compareTo(right.kind.index);
        if (kindOrder != 0) return kindOrder;
        return left.displayName.compareTo(right.displayName);
      });
    return ranked.take(18).toList(growable: false);
  }

  Future<List<MailRecipientSuggestion>> _loadOrganizationSuggestions() async {
    final organizations =
        _index?.organizations ?? await _directoryService.loadOrganizations();
    final suggestions = <MailRecipientSuggestion>[];
    for (final organization in organizations) {
      final organizationValues = <String>[
        organization.nameCn,
        organization.nameEn,
        organization.shortName,
        organization.office,
      ];
      for (final email in organization.emails) {
        suggestions.add(
          MailRecipientSuggestion(
            email: email,
            displayName: organization.nameCn.isNotEmpty
                ? organization.nameCn
                : organization.nameEn,
            contextLabel: organization.shortName.isNotEmpty
                ? organization.shortName
                : organization.office,
            kind: MailRecipientKind.organization,
            searchValues: [...organizationValues, email],
          ),
        );
      }
      for (final contact in [
        ...organization.contacts,
        ...organization.services,
      ]) {
        for (final email in contact.emails) {
          suggestions.add(
            MailRecipientSuggestion(
              email: email,
              displayName: contact.nameCn.isNotEmpty
                  ? contact.nameCn
                  : (contact.nameEn.isNotEmpty
                        ? contact.nameEn
                        : organization.nameCn),
              contextLabel: [
                organization.nameCn,
                contact.office,
              ].where((value) => value.isNotEmpty).join(' · '),
              kind: MailRecipientKind.person,
              searchValues: [
                ...organizationValues,
                contact.nameCn,
                contact.nameEn,
                contact.office,
                ...contact.responsibilities,
                email,
              ],
              personNames: [contact.nameCn, contact.nameEn],
            ),
          );
        }
      }
      suggestions.addAll(
        organization.embeddedStaff.expand(
          (teacher) =>
              {
                if (teacher.email.isNotEmpty) teacher.email,
                ...teacher.contactEmails,
              }.map(
                (email) => _teacherSuggestion(
                  teacher,
                  email: email,
                  fallbackContext: organization.nameCn,
                  extraSearchValues: organizationValues,
                ),
              ),
        ),
      );
    }
    return suggestions;
  }

  static MailRecipientSuggestion _teacherSuggestion(
    OfficialTeacherProfile teacher, {
    required String fallbackContext,
    String? email,
    List<String> extraSearchValues = const [],
  }) {
    final context = [
      ...teacher.unitNames,
      teacher.position,
      teacher.title,
      teacher.office,
    ].where((value) => value.isNotEmpty).join(' · ');
    return MailRecipientSuggestion(
      email: email ?? teacher.email,
      displayName: teacher.displayName,
      contextLabel: context.isNotEmpty ? context : fallbackContext,
      kind: MailRecipientKind.person,
      searchValues: [
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
        ...teacher.unitNames,
        ...extraSearchValues,
      ],
      personNames: [teacher.name, teacher.nameEn],
    );
  }

  static int _score(MailRecipientSuggestion item, String query) {
    if (query.isEmpty) {
      return item.kind == MailRecipientKind.organization ? 2 : 4;
    }
    final email = item.email.trim().toLowerCase();
    final localPart = email.split('@').first;
    if (email == query) return 0;
    if (query.contains('@')) return 100;
    if (localPart == query) return 1;
    if (localPart.startsWith(query)) return 2;
    if (localPart.contains(query)) return 7;
    if (RegExp(r'[._+\-]').hasMatch(query)) return 100;
    final name = _normalize(item.displayName);
    if (name == _normalize(query)) return 4;
    final directoryScore = DirectorySearch.score(
      query,
      values: item.searchValues,
      personNames: item.personNames,
    );
    return directoryScore == DirectorySearch.noMatch
        ? 100
        : 10 + directoryScore;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s·_\-—（）()]+'), '');
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && at == value.lastIndexOf('@') && at < value.length - 3;
  }

  void dispose() {
    if (_ownsDirectoryService) {
      _directoryService.dispose();
    }
  }
}
