import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Only explicitly empty reports are empty; unrecognized structure is unavailable.
enum GradeReportAvailability { available, empty, unavailable }

class GradeReportCourse {
  const GradeReportCourse({
    required this.code,
    required this.title,
    required this.unitAttempted,
    required this.unitGained,
    required this.grade,
    required this.gradePoint,
    required this.score,
    required this.remarkCode,
  });

  final String code;
  final String title;
  final double unitAttempted;
  final double unitGained;
  final String grade;

  /// The school's weighted grade points, not a locally calculated GPA.
  final double? gradePoint;
  final String score;
  final String remarkCode;
}

class GradeReportSemester {
  GradeReportSemester({
    required this.label,
    required List<GradeReportCourse> courses,
    this.unitAttempted,
    this.unitGained,
    this.gradePoints,
    this.gpa,
    List<String> distinctions = const [],
  }) : courses = List.unmodifiable(courses),
       distinctions = List.unmodifiable(distinctions);

  final String label;
  final List<GradeReportCourse> courses;
  final double? unitAttempted;
  final double? unitGained;
  final double? gradePoints;
  final double? gpa;
  final List<String> distinctions;
}

class GradeReport {
  GradeReport({
    required this.availability,
    required List<GradeReportSemester> semesters,
    required List<MisAcademicYearOption> academicYears,
    this.cumulativeUnitAttempted,
    this.cumulativeUnitGained,
    this.cumulativeGradePoints,
    this.cumulativeGpa,
  }) : semesters = List.unmodifiable(semesters),
       academicYears = List.unmodifiable(academicYears);

  const GradeReport.unavailable()
    : availability = GradeReportAvailability.unavailable,
      semesters = const [],
      academicYears = const [],
      cumulativeUnitAttempted = null,
      cumulativeUnitGained = null,
      cumulativeGradePoints = null,
      cumulativeGpa = null;

  final GradeReportAvailability availability;
  final List<GradeReportSemester> semesters;
  final List<MisAcademicYearOption> academicYears;
  final double? cumulativeUnitAttempted;
  final double? cumulativeUnitGained;
  final double? cumulativeGradePoints;

  /// School-reported only. Missing/NA GPA stays null, including repeat courses.
  final double? cumulativeGpa;

  bool get hasData => availability == GradeReportAvailability.available;
  bool get isAllAcademicYears {
    final selected = academicYears.where((year) => year.selected).toList();
    return selected.length == 1 && selected.single.isAllAcademicYears;
  }

  List<GradeReportCourse> get courses =>
      List.unmodifiable(semesters.expand((semester) => semester.courses));

  factory GradeReport.fromHtml(String source) {
    try {
      return _parseReport(html_parser.parse(source));
    } on FormatException {
      // Never return upstream content (which also contains identity information).
      return const GradeReport.unavailable();
    }
  }
}

class MisAcademicYearOption {
  const MisAcademicYearOption({
    required this.label,
    required this.value,
    required this.selected,
  });

  final String label;
  final String value;
  final bool selected;

  bool get isAllAcademicYears =>
      _text(label).toLowerCase() == 'all academic years';

  static List<MisAcademicYearOption> parseFrom(Document document) {
    final select = document.querySelector('select[name=id]');
    if (select == null) return const [];
    return List.unmodifiable([
      for (final option in select.querySelectorAll('option'))
        MisAcademicYearOption(
          label: _text(option.text),
          // Preserve opaque values exactly for form encoding.
          value: option.attributes['value'] ?? '',
          selected: option.attributes.containsKey('selected'),
        ),
    ]);
  }

  static MisAcademicYearOption? allAcademicYearsIn(String source) {
    final options = parseFrom(
      html_parser.parse(source),
    ).where((option) => option.isAllAcademicYears).toList();
    return options.length == 1 ? options.single : null;
  }
}

GradeReport _parseReport(Document document) {
  final years = MisAcademicYearOption.parseFrom(document);
  Element? table;
  Element? header;
  for (final row in document.querySelectorAll('tr')) {
    final cells = _cells(row);
    if (cells.isEmpty || _text(cells.first.text) != 'Course Code') continue;
    final labels = cells.map((cell) => _text(cell.text)).toList();
    final expected = [
      'Course Code',
      'Course Title',
      'Unit Attempted',
      'Unit Gained',
      'Grade',
      'Grade Point',
      if (labels.contains('Score')) 'Score',
      'Remarks Code',
    ];
    if (labels.join('|') != expected.join('|') ||
        cells.first.attributes['colspan'] != '2') {
      throw const FormatException('Invalid grade columns');
    }
    table = _parentTable(row);
    header = row;
    break;
  }
  if (table == null || header == null) {
    throw const FormatException('Missing grade table');
  }

  final semesters = <GradeReportSemester>[];
  _SemesterBuilder? current;
  double? cumulativeAttempted,
      cumulativeGained,
      cumulativePoints,
      cumulativeGpa;
  var started = false;
  var explicitlyEmpty = false;
  for (final row in table.querySelectorAll('tr')) {
    if (_parentTable(row) != table) continue;
    if (row == header) {
      started = true;
      continue;
    }
    if (!started) continue;
    final cells = _cells(row);
    final texts = cells.map((cell) => _text(cell.text)).toList();
    if (texts.isEmpty || texts.every((text) => text.isEmpty)) continue;
    final first = texts.first;
    if (texts.length == 1) {
      if (_semesterLabel.hasMatch(first)) {
        if (current != null) semesters.add(current.build());
        // A cumulative block belongs to the semester that precedes it. Clear
        // every field before a new semester so a missing final block cannot
        // make an earlier cumulative snapshot look current.
        cumulativeAttempted = null;
        cumulativeGained = null;
        cumulativePoints = null;
        cumulativeGpa = null;
        current = _SemesterBuilder(first);
      } else if (_gpaLabel.hasMatch(first)) {
        final match = _gpaLabel.firstMatch(first)!;
        final value = _optionalNumber(match.group(2)!);
        if (match.group(1)!.toLowerCase().contains('cumulative')) {
          cumulativeGpa = value;
        } else {
          if (current == null) throw const FormatException('Missing semester');
          current.gpa = value;
        }
      } else if (RegExp(
        r"^Dean['’]s List$",
        caseSensitive: false,
      ).hasMatch(first)) {
        if (current == null) throw const FormatException('Missing semester');
        current.distinctions.add(first);
      } else if (_emptyLabel.hasMatch(first)) {
        explicitlyEmpty = true;
      } else {
        throw const FormatException('Unrecognized grade row');
      }
      continue;
    }
    if (_totalLabel.hasMatch(first)) {
      final numbers = texts
          .skip(1)
          .where((text) => text.isNotEmpty)
          .map(_requiredNumber)
          .toList();
      if (numbers.length != 3) throw const FormatException('Invalid totals');
      if (first.toLowerCase().contains('cumulative')) {
        cumulativeAttempted = numbers[0];
        cumulativeGained = numbers[1];
        cumulativePoints = numbers[2];
        // Each cumulative block supersedes the preceding block, even if GPA is absent.
        cumulativeGpa = null;
      } else {
        if (current == null) throw const FormatException('Missing semester');
        current.attempted = numbers[0];
        current.gained = numbers[1];
        current.points = numbers[2];
      }
      continue;
    }
    // A hidden/commented Score header can have no corresponding body cell.
    // Both supported body layouts have separate department and course-number cells.
    if (current == null ||
        (texts.length != 8 && texts.length != 9) ||
        cells.any(
          (cell) => (int.tryParse(cell.attributes['colspan'] ?? '1') ?? 0) != 1,
        ) ||
        texts.take(3).any((text) => text.isEmpty)) {
      throw const FormatException('Invalid grade row');
    }
    current.courses.add(
      GradeReportCourse(
        code: '${texts[0]} ${texts[1]}',
        title: texts[2],
        unitAttempted: _requiredNumber(texts[3]),
        unitGained: _requiredNumber(texts[4]),
        grade: texts[5],
        gradePoint: _optionalNumber(texts[6]),
        score: texts.length == 9 ? texts[7] : '',
        remarkCode: texts.last,
      ),
    );
  }
  if (current != null) semesters.add(current.build());
  final hasCourses = semesters.any((semester) => semester.courses.isNotEmpty);
  if (!hasCourses && !explicitlyEmpty || hasCourses && explicitlyEmpty) {
    throw const FormatException('Ambiguous empty report');
  }
  return GradeReport(
    availability: hasCourses
        ? GradeReportAvailability.available
        : GradeReportAvailability.empty,
    semesters: semesters,
    academicYears: years,
    cumulativeUnitAttempted: cumulativeAttempted,
    cumulativeUnitGained: cumulativeGained,
    cumulativeGradePoints: cumulativePoints,
    cumulativeGpa: cumulativeGpa,
  );
}

class _SemesterBuilder {
  _SemesterBuilder(this.label);
  final String label;
  final courses = <GradeReportCourse>[];
  final distinctions = <String>[];
  double? attempted, gained, points, gpa;

  GradeReportSemester build() => GradeReportSemester(
    label: label,
    courses: courses,
    unitAttempted: attempted,
    unitGained: gained,
    gradePoints: points,
    gpa: gpa,
    distinctions: distinctions,
  );
}

final _semesterLabel = RegExp(
  r'^Semester\s+\d+\s+of\s+\d{4}\s*-\s*\d{4}$',
  caseSensitive: false,
);
final _gpaLabel = RegExp(
  r'^((?:Course\s+)?(?:Semester|Cumulative))\s+(?:Grade Point Average|GPA)\s*=\s*(.*?)\s*$',
  caseSensitive: false,
);
final _totalLabel = RegExp(
  r'^(?:Semester|(?:Course\s+)?Cumulative)\s+Total\s*:?$',
  caseSensitive: false,
);
final _emptyLabel = RegExp(
  r'^(?:No (?:grade |course |academic )?(?:records?|results?|data)(?: (?:found|available))?|No grades (?:published|available))\.?$',
  caseSensitive: false,
);

String _text(String text) =>
    text.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
List<Element> _cells(Element row) => row.children
    .where((cell) => cell.localName == 'td' || cell.localName == 'th')
    .toList();

double _requiredNumber(String text) {
  final value = double.tryParse(text.replaceAll(',', ''));
  if (value == null || !value.isFinite || value < 0) {
    throw const FormatException('Invalid grade number');
  }
  return value;
}

double? _optionalNumber(String text) {
  if (const {
    '',
    'NA',
    'N/A',
    'UNKNOWN',
    '-',
    '--',
  }.contains(text.toUpperCase())) {
    return null;
  }
  return _requiredNumber(text);
}

Element? _parentTable(Element element) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (parent.localName == 'table') return parent;
  }
  return null;
}
