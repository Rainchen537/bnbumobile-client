import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/exam_timetable.dart';

void main() {
  test('parses an English MIS exam timetable by semantic headers', () {
    final data = ExamTimetableData.fromHtml('''
      <table>
        <tr><th>No.</th><th>Course Code</th><th>Course Name</th>
          <th>Exam Date</th><th>Exam Time</th><th>Venue</th><th>Seat No.</th></tr>
        <tr><td>1</td><td>COMP1001</td><td>Programming</td>
          <td>2026-12-15</td><td>09:00 - 11:00</td><td>T2-101</td><td>18</td></tr>
      </table>
    ''');

    expect(data.availability, ExamTimetableAvailability.available);
    expect(data.entries, hasLength(1));
    expect(data.entries.single.courseCode, 'COMP1001');
    expect(data.entries.single.courseName, 'Programming');
    expect(data.entries.single.date, DateTime(2026, 12, 15));
    expect(data.entries.single.startMinutes, 9 * 60);
    expect(data.entries.single.endMinutes, 11 * 60);
    expect(data.entries.single.room, 'T2-101');
    expect(data.entries.single.seat, '18');
  });

  test('supports Chinese headers, day-first dates and 12-hour times', () {
    final data = ExamTimetableData.fromHtml('''
      <table>
        <tr><th>课程代码</th><th>课程名称</th><th>考试日期</th>
          <th>考试时间</th><th>考场</th><th>座位</th><th>备注</th></tr>
        <tr><td>MATH1001</td><td>高等数学</td><td>16/12/2026</td>
          <td>1:30 PM to 3:30 PM</td><td>T3-201</td><td>07</td><td>闭卷</td></tr>
      </table>
    ''');

    expect(data.availability, ExamTimetableAvailability.available);
    expect(data.entries.single.startMinutes, 13 * 60 + 30);
    expect(data.entries.single.endMinutes, 15 * 60 + 30);
    expect(data.entries.single.remark, '闭卷');
  });

  test('returns an empty available page without inventing exam entries', () {
    final data = ExamTimetableData.fromHtml(
      '<html><p>No examination timetable is available.</p></html>',
    );

    expect(data.availability, ExamTimetableAvailability.empty);
    expect(data.entries, isEmpty);
  });

  test('deduplicates responsive and nested copies of the same exam', () {
    const table = '''
      <table>
        <tr><th>Course Code</th><th>Course Name</th><th>Exam Date</th>
          <th>Exam Time</th><th>Venue</th><th>Seat</th><th>Remark</th></tr>
        <tr><td>COMP1001</td><td>Programming</td><td>2026-12-15</td>
          <td>09:00 - 11:00</td><td>T2-101</td><td>18</td><td>Closed book</td></tr>
      </table>
    ''';

    final responsive = ExamTimetableData.fromHtml('$table$table');
    final nested = ExamTimetableData.fromHtml(
      '<table><tr><td>$table</td></tr></table>',
    );

    expect(responsive.entries, hasLength(1));
    expect(nested.entries, hasLength(1));
  });

  test('deduplication keeps the duplicate row that contains a remark', () {
    final data = ExamTimetableData.fromHtml('''
      <table>
        <tr><th>Course Code</th><th>Course Name</th><th>Exam Date</th>
          <th>Exam Time</th><th>Venue</th><th>Seat</th><th>Remark</th></tr>
        <tr><td>COMP1001</td><td>Programming</td><td>2026-12-15</td>
          <td>09:00 - 11:00</td><td>T2-101</td><td>18</td><td></td></tr>
        <tr><td>COMP1001</td><td>Programming</td><td>2026-12-15</td>
          <td>09:00 - 11:00</td><td>T2-101</td><td>18</td><td>Closed book</td></tr>
      </table>
    ''');

    expect(data.entries, hasLength(1));
    expect(data.entries.single.remark, 'Closed book');
  });

  test('widget identity includes both course code and course name', () {
    final first = ExamTimetableEntry(
      courseCode: 'COMP1001',
      courseName: 'Programming',
      date: DateTime(2026, 12, 15),
      startMinutes: 9 * 60,
      endMinutes: 11 * 60,
      room: 'T2-101',
      seat: '18',
      remark: '',
    );
    final second = ExamTimetableEntry(
      courseCode: 'COMP1001',
      courseName: 'Programming Lab',
      date: DateTime(2026, 12, 15),
      startMinutes: 9 * 60,
      endMinutes: 11 * 60,
      room: 'T2-101',
      seat: '18',
      remark: '',
    );

    expect(first.widgetKey, isNot(second.widgetKey));
  });
}
