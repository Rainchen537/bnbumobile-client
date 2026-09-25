import 'dart:io';

import 'package:bnbu_me/models/grade_report.dart';
import 'package:flutter_test/flutter_test.dart';

String gradeReportFixture() =>
    File('test/fixtures/grade_report_all.html').readAsStringSync();

void main() {
  test(
    'eight cells ignore hidden Score; school GPA and final totals are authoritative',
    () {
      final report = GradeReport.fromHtml(gradeReportFixture());
      expect(report.availability, GradeReportAvailability.available);
      expect(report.isAllAcademicYears, isTrue);
      expect(report.semesters, hasLength(2));
      expect(report.courses, hasLength(3));
      expect(report.courses.first.code, 'DEMO 1001');
      expect(report.courses.first.grade, 'F');
      expect(report.courses.first.score, '');
      expect(report.courses.first.remarkCode, 'R');
      expect(report.courses[1].gradePoint, isNull);
      expect(report.semesters.first.gpa, 0);
      expect(report.semesters.last.gpa, 3.3);
      expect(report.cumulativeGpa, 2.75);
      expect(report.cumulativeUnitAttempted, 7);
      expect(report.cumulativeUnitGained, 4);
      expect(report.semesters.first.distinctions, isEmpty);
      expect(report.semesters.last.distinctions, ['Dean’s List']);
    },
  );

  test('nine cells preserve Score and remarks independently', () {
    final report = GradeReport.fromHtml(
      gradeReportFixture().replaceAll(
        '<td>9.9</td><td>R</td>',
        '<td>9.9</td><td>86</td><td>R</td>',
      ),
    );
    expect(report.courses.last.score, '86');
    expect(report.courses.last.gradePoint, 9.9);
    expect(report.courses.last.remarkCode, 'R');
  });

  test('commented Score header is supported', () {
    final report = GradeReport.fromHtml(
      gradeReportFixture().replaceAll(
        '<td class="score">Score</td>',
        '<!-- <td>Score</td> -->',
      ),
    );
    expect(report.courses, hasLength(3));
  });

  for (final grade in ['S', 'U', 'F', 'W', 'I', 'IP', 'Unknown']) {
    test('preserves school grade $grade with NA points', () {
      final report = GradeReport.fromHtml(
        gradeReportFixture().replaceAll('<td>S</td>', '<td>$grade</td>'),
      );
      expect(report.courses[1].grade, grade);
      expect(report.courses[1].gradePoint, isNull);
    });
  }
  for (final gpa in ['NA', 'unknown', '']) {
    test('missing GPA $gpa has no calculated fallback', () {
      final report = GradeReport.fromHtml(
        gradeReportFixture()
            .replaceAll('= 2.75', '= $gpa')
            .replaceAll('= 3.30', '= $gpa'),
      );
      expect(report.availability, GradeReportAvailability.available);
      expect(report.cumulativeGpa, isNull);
      expect(report.semesters.last.gpa, isNull);
    });
  }
  test('last cumulative block without GPA cannot inherit earlier GPA', () {
    final report = GradeReport.fromHtml(
      gradeReportFixture().replaceAll(
        '<tr><td colspan="8">Course Cumulative Grade Point Average = 2.75</td></tr>',
        '',
      ),
    );
    expect(report.cumulativeGpa, isNull);
  });

  test('final semester without any cumulative block clears earlier totals', () {
    final report = GradeReport.fromHtml(
      gradeReportFixture()
          .replaceAll(
            '<tr><td colspan="3">Course Cumulative Total</td><td>7</td><td>4</td><td></td><td>9.9</td><td></td></tr>',
            '',
          )
          .replaceAll(
            '<tr><td colspan="8">Course Cumulative Grade Point Average = 2.75</td></tr>',
            '',
          ),
    );
    expect(report.availability, GradeReportAvailability.available);
    expect(report.cumulativeUnitAttempted, isNull);
    expect(report.cumulativeUnitGained, isNull);
    expect(report.cumulativeGradePoints, isNull);
    expect(report.cumulativeGpa, isNull);
  });

  test('unsupported semester title fails closed instead of merging terms', () {
    final report = GradeReport.fromHtml(
      gradeReportFixture().replaceAll(
        'Semester 2 of 2030-2031',
        'Semester 2 of 2030-31',
      ),
    );
    expect(report.availability, GradeReportAvailability.unavailable);
  });
  test('format failures never become empty or partial success', () {
    for (final source in [
      '<html>service unavailable</html>',
      gradeReportFixture().replaceAll(
        '<td>Unit Gained</td>',
        '<td>Unknown</td>',
      ),
      gradeReportFixture().replaceAll(
        '<td>9.9</td><td>R</td>',
        '<td>broken</td><td>R</td>',
      ),
      gradeReportFixture().replaceAll('<td>NA</td><td>*</td>', '<td>NA</td>'),
    ]) {
      expect(
        GradeReport.fromHtml(source).availability,
        GradeReportAvailability.unavailable,
      );
    }
  });
  test('only explicit empty table is empty', () {
    final fixture = gradeReportFixture();
    final headerEnd =
        fixture.indexOf('</tr>', fixture.indexOf('Course Code')) + 5;
    final prefix = fixture.substring(0, headerEnd);
    expect(
      GradeReport.fromHtml('$prefix</table>').availability,
      GradeReportAvailability.unavailable,
    );
    final empty = GradeReport.fromHtml(
      '$prefix<tr><td colspan="8">No records found.</td></tr></table>',
    );
    expect(empty.availability, GradeReportAvailability.empty);
    expect(empty.isAllAcademicYears, isTrue);
  });
  test(
    'all collections are immutable snapshots including constructor inputs',
    () {
      final courses = <GradeReportCourse>[];
      final distinctions = <String>[];
      final semester = GradeReportSemester(
        label: 'sample',
        courses: courses,
        distinctions: distinctions,
      );
      final semesters = [semester];
      final years = <MisAcademicYearOption>[];
      final report = GradeReport(
        availability: GradeReportAvailability.empty,
        semesters: semesters,
        academicYears: years,
      );
      semesters.clear();
      distinctions.add('fake');
      expect(report.semesters, hasLength(1));
      expect(semester.distinctions, isEmpty);
      expect(() => semester.courses.clear(), throwsUnsupportedError);
      expect(() => report.semesters.clear(), throwsUnsupportedError);
      expect(() => report.academicYears.clear(), throwsUnsupportedError);
      expect(() => report.courses.clear(), throwsUnsupportedError);
    },
  );
}
