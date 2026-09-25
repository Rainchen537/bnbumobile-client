import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/academic_calendar_service.dart';

void main() {
  test('parses replacement PDF links only for the pinned semester', () {
    final bundle = parseAcademicCalendarIndex('''
      <a href="/attachment/file/calendar-revised.pdf">
        Academic Calendar for S1 of AY2026-27.pdf
      </a>
      <a href="/attachment/file/schedule-revised.pdf">
        Class Schedule for S1 of AY2026-27.pdf
      </a>
      <a href="/attachment/file/calendar-s2.pdf">
        Academic Calendar for S2 of AY2026-27.pdf
      </a>
    ''');

    expect(
      bundle.academicCalendar.uri.path,
      '/attachment/file/calendar-revised.pdf',
    );
    expect(
      bundle.classSchedule.uri.path,
      '/attachment/file/schedule-revised.pdf',
    );
  });

  test('rejects replacement links outside the official registry host', () {
    expect(
      () => parseAcademicCalendarIndex('''
        <a href="https://example.com/calendar.pdf">
          Academic Calendar for S1 of AY2026-27.pdf
        </a>
        <a href="/attachment/file/schedule.pdf">
          Class Schedule for S1 of AY2026-27.pdf
        </a>
      '''),
      throwsA(isA<AcademicCalendarException>()),
    );
  });

  test('accepts only the default HTTPS port for official documents', () {
    expect(
      () => parseAcademicCalendarIndex('''
        <a href="https://ar.bnbu.edu.cn:8443/attachment/file/calendar.pdf">
          Academic Calendar for S1 of AY2026-27.pdf
        </a>
        <a href="/attachment/file/schedule.pdf">
          Class Schedule for S1 of AY2026-27.pdf
        </a>
      '''),
      throwsA(isA<AcademicCalendarException>()),
    );

    final bundle = parseAcademicCalendarIndex('''
      <a href="https://ar.bnbu.edu.cn:443/attachment/file/calendar.pdf">
        Academic Calendar for S1 of AY2026-27.pdf
      </a>
      <a href="https://ar.bnbu.edu.cn:443/attachment/file/schedule.pdf">
        Class Schedule for S1 of AY2026-27.pdf
      </a>
    ''');
    expect(bundle.academicCalendar.uri.port, 443);
    expect(bundle.classSchedule.uri.port, 443);
  });

  test('rejects query parameters on official PDF links', () {
    expect(
      () => parseAcademicCalendarIndex('''
        <a href="https://ar.bnbu.edu.cn/attachment/file/calendar.pdf?next=https://evil.example/file">
          Academic Calendar for S1 of AY2026-27.pdf
        </a>
        <a href="/attachment/file/schedule.pdf">
          Class Schedule for S1 of AY2026-27.pdf
        </a>
      '''),
      throwsA(isA<AcademicCalendarException>()),
    );
  });

  test(
    'repository downloads the current links resolved from the index',
    () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path.endsWith('Academic_Calendar.htm')) {
          return http.Response('''
          <a href="/attachment/file/calendar-current.pdf">
            Academic Calendar for S1 of AY2026-27.pdf
          </a>
          <a href="/attachment/file/schedule-current.pdf">
            Class Schedule for S1 of AY2026-27.pdf
          </a>
        ''', 200);
        }
        return http.Response.bytes(utf8.encode('%PDF-1.7\nverified'), 200);
      });

      final snapshot = await OfficialAcademicCalendarRepository(
        client: client,
      ).load();

      expect(requestedPaths, contains('/attachment/file/calendar-current.pdf'));
      expect(requestedPaths, contains('/attachment/file/schedule-current.pdf'));
      expect(snapshot.academicCalendarBytes, isNotEmpty);
      expect(snapshot.classScheduleBytes, isNotEmpty);
    },
  );

  test(
    'metadata-only bundle loading reads the index without downloading PDFs',
    () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response('''
        <a href="/attachment/file/calendar-current.pdf">
          Academic Calendar for S1 of AY2026-27.pdf
        </a>
        <a href="/attachment/file/schedule-current.pdf">
          Class Schedule for S1 of AY2026-27.pdf
        </a>
      ''', 200);
      });

      final bundle = await OfficialAcademicCalendarRepository(
        client: client,
      ).loadBundle();

      expect(bundle.semesterTitle, 'Semester 1 of AY2026-27');
      expect(requestedPaths, [
        '/current_students/student_handbook/Academic_Calendar.htm',
      ]);
    },
  );
}
