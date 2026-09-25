import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/academic_calendar.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/services/academic_calendar_service.dart';
import 'package:bnbu_me/services/academic_calendar_store.dart';
import 'package:bnbu_me/state/app_session_controller.dart';

String _date(DateTime date) => date.toIso8601String().split('T').first;

// Test fixture is generated solely from the client public built-in rules.
Map<String, dynamic> snapshot([int version = 2]) {
  final term = BnbuAcademicCalendar.builtIn;
  return jsonDecode(
        jsonEncode({
          'schema_version': 1,
          'version': version,
          'catalog': {
            'default_semester_id': term.id,
            'semesters': [
              {
                'id': term.id,
                'academic_year_start': term.academicYearStart,
                'semester': term.semester,
                'semester_title': term.semesterTitle,
                'semester_ids': <String>[],
                'semester_starts_on': _date(term.semesterStartsOn),
                'last_class_day': _date(term.lastClassDay),
                'events': [
                  for (final e in term.events)
                    {
                      'kind': e.kind.wireValue,
                      'name': e.name,
                      'starts_on': _date(e.startsOn),
                      'ends_on': _date(e.endsOn),
                      'reason': e.reason,
                      'source_weekday': e.sourceWeekday,
                      'notice': e.notice,
                    },
                ],
                'documents': {
                  'academic_calendar': {
                    'title': 'Synthetic calendar.pdf',
                    'url':
                        'https://ar.bnbu.edu.cn/attachment/file/test-calendar.pdf',
                  },
                  'class_schedule': {
                    'title': 'Synthetic schedule.pdf',
                    'url':
                        'https://ar.bnbu.edu.cn/attachment/file/test-schedule.pdf',
                  },
                },
              },
            ],
          },
        }),
      )
      as Map<String, dynamic>;
}

TimetableData timetable([
  String id = '2026-27-S1',
  String name = 'Semester 1 of AY2026-27',
]) => TimetableData.fromJson({
  'selectedSemesterId': id,
  'selectedSemesterName': name,
  'profile': <String, dynamic>{},
  'semesters': [],
  'courses': [],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BnbuAcademicCalendar.install(null);
  });
  tearDown(() => BnbuAcademicCalendar.install(null));
  test('remote seed preserves every existing class-day result', () {
    final t = timetable();
    final before = [
      for (var i = 0; i < 370; i++)
        BnbuAcademicCalendar.classDayFor(t, DateTime(2026, 8, 1 + i)),
    ];
    BnbuAcademicCalendar.install(BnbuCalendarCatalog.fromJson(snapshot()));
    expect(BnbuAcademicCalendar.events.length, 21);
    for (var i = 0; i < 370; i++) {
      final after = BnbuAcademicCalendar.classDayFor(
        t,
        DateTime(2026, 8, 1 + i),
      );
      expect(after.sourceWeekday, before[i].sourceWeekday, reason: 'day $i');
      expect(after.notice, before[i].notice, reason: 'notice $i');
    }
  });
  test(
    'next academic year works without changing callers or event names',
    () async {
      final data = snapshot();
      final catalog = data['catalog'] as Map<String, dynamic>;
      final term = (catalog['semesters'] as List).first as Map<String, dynamic>;
      term['id'] = '2027-28-s2';
      term['academic_year_start'] = 2027;
      term['semester'] = 2;
      term['semester_title'] = 'Semester 2 of AY2027-28';
      term['semester_starts_on'] = '2028-02-01';
      term['last_class_day'] = '2028-06-01';
      term['events'] = [
        {
          'kind': 'holiday',
          'name': 'Changed display name',
          'starts_on': '2028-03-01',
          'ends_on': '2028-03-03',
        },
        {
          'kind': 'make_up_class',
          'name': 'New make-up event',
          'starts_on': '2028-03-04',
          'ends_on': '2028-03-04',
          'source_weekday': 1,
        },
      ];
      catalog['default_semester_id'] = term['id'];
      BnbuAcademicCalendar.install(BnbuCalendarCatalog.fromJson(data));
      final t = timetable('2027-28-S2', 'Semester 2 of AY2027-28');
      expect(BnbuAcademicCalendar.appliesTo(t), isTrue);
      expect(
        BnbuAcademicCalendar.classDayFor(t, DateTime(2028, 3, 2)).hasClasses,
        isFalse,
      );
      expect(
        BnbuAcademicCalendar.classDayFor(t, DateTime(2028, 3, 4)).sourceWeekday,
        1,
      );
      expect(
        BnbuAcademicCalendar.classDayFor(t, DateTime(2028, 6, 2)).hasClasses,
        isFalse,
      );
      expect(
        BnbuAcademicCalendar.appliesTo(
          timetable('2027-28-S1', 'Semester 1 of AY2027-28'),
        ),
        isFalse,
      );
      expect(BnbuAcademicCalendar.appliesTo(timetable()), isTrue);
      final repo = OfficialAcademicCalendarRepository();
      expect((await repo.loadBundle()).semesterTitle, term['semester_title']);
    },
  );
  test(
    'winter training is independent of other terms and survives reload',
    () async {
      final data = snapshot();
      final catalog = data['catalog'] as Map<String, dynamic>;
      final winter = Map<String, dynamic>.from(catalog['semesters'][0] as Map)
        ..addAll({
          'id': '2026-27-winter',
          'semester': 4,
          'semester_title': '冬季学期（军训）',
          'semester_ids': ['test-winter-term'],
          'semester_starts_on': '2027-01-04',
          'last_class_day': '2027-01-15',
          'events': <dynamic>[],
        });
      (catalog['semesters'] as List).add(winter);
      catalog['default_semester_id'] = winter['id'];
      final parsed = BnbuCalendarCatalog.fromJson(jsonDecode(jsonEncode(data)));
      BnbuAcademicCalendar.install(parsed);
      final term = parsed.current!;
      expect(term.semester, 4);
      for (final name in [
        'Winter Term of AY2026-27',
        'Military Training of AY2026-27',
        '2026-2027 冬季学期（军训）',
        '2026-2027 冬季學期（軍訓）',
      ]) {
        expect(term.matches(timetable('', name)), isTrue, reason: name);
      }
      expect(term.matches(timetable('test-winter-term', '')), isTrue);
      for (final name in [
        'Semester 1 of AY2026-27',
        'Semester II of AY2026-27',
        'Summer Term of AY2026-27',
        'Winter Term of AY2025-26',
        'Winter Term of AY2027-28',
        'Winter Term',
        'Semester 4 of AY2026-27',
      ]) {
        expect(term.matches(timetable('', name)), isFalse, reason: name);
      }
      expect(BnbuAcademicCalendar.semesterFor(timetable())!.semester, 1);
      final context = BnbuAcademicCalendar.contextFor(
        timetable('test-winter-term', ''),
      );
      expect(context.appliesToSelectedSemester, isTrue);
      expect(context.semesterTitle, '冬季学期（军训）');
      expect(context.semesterStartsOn, DateTime(2027, 1, 4));
      final repo = OfficialAcademicCalendarRepository();
      expect((await repo.loadBundle()).semesterTitle, '冬季学期（军训）');
    },
  );
  test('invalid dates, rules, versions and unsafe PDFs are rejected', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (p) => p['schema_version'] = 2,
      (p) => p['catalog']['semesters'][0]['semester'] = 0,
      (p) => p['catalog']['semesters'][0]['semester'] = 5,
      (p) =>
          p['catalog']['semesters'][0]['events'][0]['starts_on'] = '2026-02-30',
      (p) => p['catalog']['semesters'][0]['events'][5]['source_weekday'] = null,
      (p) =>
          p['catalog']['semesters'][0]['documents']['academic_calendar']['url'] =
              'https://evil.example/calendar.pdf',
      (p) => p['catalog']['semesters'][0]['events'].add(
        p['catalog']['semesters'][0]['events'][6],
      ),
      (p) => p['catalog']['semesters'].add(p['catalog']['semesters'][0]),
    ]) {
      final data = snapshot();
      mutate(data);
      expect(() => BnbuCalendarCatalog.fromJson(data), throwsA(anything));
    }
  });
  test('validated updates notify existing session consumers', () async {
    final controller = AppSessionController();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final before = notifications;
    BnbuAcademicCalendar.install(BnbuCalendarCatalog.fromJson(snapshot()));
    expect(notifications, greaterThan(before));
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });
  test(
    'cache survives restart and failed, stale, conflicting, or redirected updates',
    () async {
      final root = await Directory.systemTemp.createTemp('calendar-test-');
      addTearDown(() => root.delete(recursive: true));
      var response = http.Response.bytes(
            utf8.encode(jsonEncode(snapshot())),
            200,
          ),
          calls = 0,
          updates = 0;
      final store = AcademicCalendarStore(
        directory: () async => root,
        client: MockClient((request) async {
          calls++;
          if (calls > 1) {
            expect(request.headers['If-None-Match'], '"academic-calendar-2"');
          }
          return response;
        }),
        onUpdate: (c) {
          updates++;
        },
      );
      await store.refresh();
      expect(store.catalog!.version, 2);
      expect(updates, 1);
      response = http.Response('', 304);
      await store.refresh(force: true);
      expect(updates, 1);
      response = http.Response.bytes(utf8.encode(jsonEncode(snapshot(1))), 200);
      await store.refresh(force: true);
      expect(store.catalog!.version, 2);
      final broken = snapshot(3);
      broken['catalog']['semesters'][0]['last_class_day'] = 'bad';
      response = http.Response.bytes(utf8.encode(jsonEncode(broken)), 200);
      await store.refresh(force: true);
      expect(store.failed, isTrue);
      expect(store.catalog!.version, 2);
      response = http.Response(
        '',
        302,
        headers: {'location': 'https://evil.example'},
      );
      await store.refresh(force: true);
      expect(store.catalog!.version, 2);
      store.dispose();
      final restarted = AcademicCalendarStore(
        directory: () async => root,
        client: MockClient((_) async => throw const SocketException('offline')),
        onUpdate: (_) {},
      );
      await restarted.refresh();
      expect(restarted.catalog!.version, 2);
      expect(restarted.failed, isTrue);
      restarted.dispose();
    },
  );
}
