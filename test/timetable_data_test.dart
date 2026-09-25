import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/exam_timetable.dart';
import 'package:bnbu_me/models/timetable_data.dart';

void main() {
  test('meeting parser accepts whitespace around the time separator', () {
    final meeting = TimetableMeeting.tryParse(
      'Mon 09:00 - 09:50',
      room: 'T3-101',
    );

    expect(meeting, isNotNull);
    expect(meeting?.weekday, DateTime.monday);
    expect(meeting?.startMinutes, 540);
    expect(meeting?.endMinutes, 590);
    expect(meeting?.room, 'T3-101');
  });

  test('timetable parser preserves multiple teacher boundaries', () {
    final timetable = TimetableData.fromHtml('''
      <select id="semesterList">
        <option value="term" selected>Semester</option>
      </select>
      <table class="tablestyle-2">
        <tr>
          <th>1</th>
          <td>Category</td>
          <td>COMP1001</td>
          <td>Programming</td>
          <td>Teacher One<br>Teacher Two</td>
          <td>Mon 09:00 - 09:50</td>
          <td>T3-101</td>
          <td>3</td>
          <td></td>
        </tr>
      </table>
    ''');

    expect(timetable.courses.single.teacher, 'Teacher One; Teacher Two');
  });

  test('timetable cache JSON preserves the complete course structure', () {
    final original = TimetableData(
      profile: TimetableProfile(
        studentId: 'student',
        name: 'Student',
        programme: 'Programme',
        year: '2',
      ),
      semesters: [
        TimetableSemester(
          id: '2026',
          name: '2026 Semester 1',
          isSelected: true,
        ),
      ],
      selectedSemesterId: '2026',
      selectedSemesterName: '2026 Semester 1',
      courses: [
        TimetableCourse(
          section: '1',
          category: 'Core',
          code: 'COMP1001',
          name: 'Programming',
          teacher: 'Teacher One; Teacher Two',
          meetings: [
            TimetableMeeting(
              weekday: DateTime.monday,
              dayLabel: 'Mon',
              startLabel: '09:00',
              endLabel: '09:50',
              startMinutes: 540,
              endMinutes: 590,
              room: 'T3-101',
            ),
          ],
          rooms: const ['T3-101'],
          units: '3',
          remark: 'Lab required',
        ),
      ],
      examAvailability: ExamTimetableAvailability.available,
      exams: [
        ExamTimetableEntry(
          courseCode: 'COMP1001',
          courseName: 'Programming',
          date: DateTime(2026, 12, 15),
          startMinutes: 9 * 60,
          endMinutes: 11 * 60,
          room: 'T2-101',
          seat: '18',
          remark: '',
        ),
      ],
    );

    final decoded = jsonDecode(jsonEncode(original.toJson()));
    final decodedMap = decoded as Map<String, dynamic>;
    final cachedExams = decodedMap['exams']! as List<dynamic>;
    cachedExams.add(
      Map<String, dynamic>.from(cachedExams.single as Map<String, dynamic>),
    );
    final restored = TimetableData.fromJson(decodedMap);

    expect(restored.profile.studentId, 'student');
    expect(restored.semesters.single.isSelected, isTrue);
    expect(restored.selectedSemesterName, '2026 Semester 1');
    expect(restored.courses.single.code, 'COMP1001');
    expect(restored.courses.single.teacher, 'Teacher One; Teacher Two');
    expect(restored.courses.single.rooms, const ['T3-101']);
    expect(restored.courses.single.meetings.single.startMinutes, 540);
    expect(restored.courses.single.meetings.single.room, 'T3-101');
    expect(restored.examAvailability, ExamTimetableAvailability.available);
    expect(restored.exams, hasLength(1));
    expect(restored.exams.single.courseCode, 'COMP1001');
    expect(restored.exams.single.date, DateTime(2026, 12, 15));
    expect(restored.exams.single.seat, '18');
  });
}
