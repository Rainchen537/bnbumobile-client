import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/state/app_session_controller.dart';

/// Fictional offline data matching campus_ui_demo revision 03. Never imported
/// by lib/ or the production main entry point.
class HomeNavigationFixture extends AppSessionController {
  HomeNavigationFixture({this.scene = 'normal'});
  final String scene;
  static final now = DateTime.utc(2026, 9, 7, 1);
  int timetableRefreshes = 0;
  int deadlineRefreshes = 0;

  @override
  bool get isLoggedIn => true;
  @override
  String? get username => null;
  @override
  bool get isLoadingTimetable => scene == 'loading';
  @override
  bool get isLoadingTimeline => scene == 'loading';
  @override
  String? get timetableError =>
      scene == 'error' ? 'Offline fixture error' : null;
  @override
  String? get error => scene == 'error' ? 'Offline fixture error' : null;
  @override
  Future<void> refreshTimetable() async {
    timetableRefreshes++;
  }

  @override
  Future<void> refreshTimeline() async {
    deadlineRefreshes++;
  }

  @override
  TimetableData get timetable => TimetableData(
    profile: TimetableProfile(studentId: '', name: '', programme: '', year: ''),
    semesters: const [],
    selectedSemesterId: 'demo-2026-27-1',
    selectedSemesterName: 'Semester 1 of AY2026-27',
    courses: scene == 'normal' || scene == 'long'
        ? [
            _course(
              'COMP 3023',
              scene == 'long'
                  ? 'Human–Computer Interaction: Inclusive Systems, Research and Prototyping'
                  : 'Human–Computer Interaction',
              'Alex Chen',
              10 * 60,
              11 * 60 + 50,
              'T29 / 203',
            ),
            _course(
              'MATH 2003',
              '概率论与数理统计',
              'Lin Zhao',
              14 * 60,
              15 * 60 + 50,
              'T28 / 302',
            ),
            _course(
              'ENG 2000',
              'Academic Writing',
              'Emma Wong',
              16 * 60,
              16 * 60 + 50,
              'T6 / 401',
            ),
          ]
        : [],
  );

  @override
  List<TimelineItem> get timelineItems => scene == 'normal' || scene == 'long'
      ? [
          _deadline(
            1,
            7,
            23,
            59,
            scene == 'long'
                ? 'Assignment 01: Understanding users and evaluating accessible campus experiences'
                : 'Assignment 01: Understanding users',
            'Human–Computer Interaction',
            '未提交',
          ),
          _deadline(2, 8, 18, 0, 'Problem Set 02', '概率论与数理统计', '草稿'),
          _deadline(
            3,
            11,
            23,
            59,
            'Reading response',
            'Academic Writing',
            '已提交',
          ),
        ]
      : [];
}

TimetableCourse _course(
  String code,
  String name,
  String teacher,
  int start,
  int end,
  String room,
) => TimetableCourse(
  section: '1001',
  category: '',
  code: code,
  name: name,
  teacher: teacher,
  meetings: [
    TimetableMeeting(
      weekday: DateTime.monday,
      dayLabel: 'Mon',
      startLabel: '${start ~/ 60}:00',
      endLabel: '${end ~/ 60}:${end % 60}',
      startMinutes: start,
      endMinutes: end,
      room: room,
    ),
  ],
  rooms: [room],
  units: '',
  remark: '',
);

TimelineItem _deadline(
  int id,
  int day,
  int hour,
  int minute,
  String title,
  String course,
  String state,
) => TimelineItem(
  id: id,
  title: title,
  activityState: state,
  activityType: 'assign',
  moduleName: 'assign',
  description: '',
  courseName: course,
  courseId: id,
  instanceId: id,
  url: '',
  sortTime: DateTime.utc(2026, 9, day, hour - 8, minute),
  formattedTime: '',
  isOverdue: false,
);
