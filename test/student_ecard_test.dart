import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/services/ecard_brightness_controller.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/student_code39_barcode.dart';

void main() {
  testWidgets('eCard keeps portrait, identity and Code 39 student payload', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const data = StudentEcardData(
      fullName: '测试学生',
      studentId: '2099000001',
      department: 'FST',
      identity: 'BNBU Student UG/STUDENT',
      gender: '男/MALE',
      residence: 'V24-101',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StudentEcardView(data: data)),
      ),
    );
    await tester.pump();

    expect(find.text('测试学生'), findsOneWidget);
    expect(find.text('FST'), findsOneWidget);
    expect(find.text('男/MALE'), findsOneWidget);
    expect(find.text('BNBU Student UG/STUDENT'), findsOneWidget);
    expect(find.text('2099000001'), findsOneWidget);
    expect(find.text('U02099000001'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('student-ecard-portrait')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('student-ecard-barcode')), findsOneWidget);

    final barcode = tester.widget<StudentCode39Barcode>(
      find.byType(StudentCode39Barcode),
    );
    expect(data.barcodePayload, 'U02099000001');
    expect(barcode.payload, 'U02099000001');

    final portrait = tester.getRect(
      find.byKey(const ValueKey('student-ecard-portrait')),
    );
    final name = tester.getRect(
      find.byKey(const ValueKey('student-ecard-name')),
    );
    final barcodeRect = tester.getRect(
      find.byKey(const ValueKey('student-ecard-barcode')),
    );
    expect(portrait.width, 140);
    expect(portrait.height, 154);
    expect(barcodeRect.width, 342);
    expect(barcodeRect.height, 82);
    expect(name.top, greaterThan(portrait.bottom));
    expect(barcodeRect.top, greaterThan(name.bottom));
    expect(find.text('••••••••'), findsNothing);
    expect(find.text('V24-101'), findsNothing);
    expect(
      find.byKey(const ValueKey('student-ecard-toggle-residence')),
      findsNothing,
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eCard remains scrollable on a narrow phone with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: StudentEcardView(
              data: StudentEcardData(
                fullName: 'Student Name',
                studentId: '12345678901234567890123456789012',
                department: 'Faculty of Science and Technology',
                identity: 'BNBU Student UG/STUDENT',
                gender: '女/FEMALE',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('student-ecard-scroll-view')),
      findsOneWidget,
    );
    expect(find.text('U012345678901234567890123456789012'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eCard brightens only while visible and restores on background', (
    tester,
  ) async {
    final sessionController = AppSessionController();
    final brightnessController = _RecordingEcardBrightnessController();
    addTearDown(sessionController.dispose);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StudentEcardPage(
          controller: sessionController,
          onGoToUser: () {},
          brightnessController: brightnessController,
        ),
      ),
    );
    await tester.pump();
    expect(brightnessController.events, ['begin']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(brightnessController.events, ['begin', 'end']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(brightnessController.events, ['begin', 'end', 'begin']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(brightnessController.events, ['begin', 'end', 'begin', 'end']);
  });

  testWidgets(
    'eCard uses the reference identity colors while Code 39 stays available',
    (tester) async {
      final sessionController = AppSessionController();
      final brightnessController = _RecordingEcardBrightnessController();
      addTearDown(sessionController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: StudentEcardPage(
            controller: sessionController,
            onGoToUser: () {},
            brightnessController: brightnessController,
          ),
        ),
      );
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(scaffold.backgroundColor, Colors.white);

      expect(appBar.backgroundColor, Colors.white);
      expect(appBar.foregroundColor, Colors.black);

      const data = StudentEcardData(
        fullName: '测试学生',
        studentId: '2099000001',
        department: 'FST',
        identity: 'BNBU Student UG/STUDENT',
        gender: '男/MALE',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: StudentEcardView(data: data)),
        ),
      );
      await tester.pump();

      final name = tester.widget<Text>(
        find.byKey(const ValueKey('student-ecard-name')),
      );
      final barcode = tester.widget<StudentCode39Barcode>(
        find.byType(StudentCode39Barcode),
      );
      expect(name.style?.color, const Color(0xFF292929));
      expect(barcode.payload, 'U02099000001');
    },
  );

  test('eCard uses explicit college instead of Student or the major', () {
    final data = _ecardData(college: 'FST');

    expect(data.department, 'FST');
    expect(data.department, isNot('Student'));
    expect(data.department, isNot('Data Science'));
  });

  test(
    'eCard maps a known major to a college code without showing the major',
    () {
      final data = _ecardData(college: '');

      expect(data.department, 'FST');
      expect(data.department, isNot('Student'));
      expect(data.department, isNot('Data Science'));
    },
  );

  test('eCard distinguishes undergraduate and postgraduate identities', () {
    expect(
      _ecardData(college: 'FST', identity: 'BNBU Student UG/STUDENT').identity,
      'BNBU Student UG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        studentLevel: 'Undergraduate',
      ).identity,
      'BNBU Student UG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        studentLevel: 'Taught Postgraduate',
      ).identity,
      'BNBU Student TPG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        studentLevel: 'Research Postgraduate',
      ).identity,
      'BNBU Student RPG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        studentLevel: 'Postgraduate',
      ).identity,
      'BNBU Student PG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        courseCodes: const <String>['COMP1001', 'STAT2003'],
      ).identity,
      'BNBU Student UG/STUDENT',
    );
    expect(
      _ecardData(
        college: 'FST',
        identity: 'Student',
        courseCodes: const <String>['DSBS7030'],
      ).identity,
      'BNBU Student PG/STUDENT',
    );
    expect(
      _ecardData(college: 'FST', identity: 'Student').identity,
      'BNBU Student/STUDENT',
    );
  });
}

class _RecordingEcardBrightnessController implements EcardBrightnessController {
  final List<String> events = <String>[];

  @override
  Future<void> begin() async {
    events.add('begin');
  }

  @override
  Future<void> end() async {
    events.add('end');
  }
}

StudentEcardData _ecardData({
  required String college,
  String identity = 'BNBU Student UG/STUDENT',
  String studentLevel = '',
  List<String> courseCodes = const <String>[],
}) {
  return StudentEcardData.fromSources(
    portal: PortalAccountProfile(
      fullName: '测试学生',
      identity: identity,
      organization: 'Student',
      department: 'Data Science',
      avatarPath: '',
      college: college,
      studentLevel: studentLevel,
      gender: '男',
    ),
    timetableProfile: TimetableProfile(
      studentId: '2099000001',
      name: '测试学生',
      programme: 'Data Science',
      year: '1',
    ),
    timetableCourseCodes: courseCodes,
    username: '2099000001',
  );
}
