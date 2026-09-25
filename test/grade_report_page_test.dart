import 'dart:async';

import 'package:bnbu_me/models/grade_report.dart';
import 'package:bnbu_me/pages/grade_report_page.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/services/home_card_visibility_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

const _first = 'Semester 1 of 2025-2026';
const _second = 'Semester 2 of 2025-2026';
const _title = 'Synthetic advanced mathematics and computational systems';

GradeReport _report({double? gpa = 3.17}) => GradeReport(
  availability: GradeReportAvailability.available,
  academicYears: const [
    MisAcademicYearOption(
      label: 'All Academic Years',
      value: 'all',
      selected: true,
    ),
  ],
  cumulativeGpa: gpa,
  cumulativeUnitAttempted: 6,
  cumulativeUnitGained: 6,
  semesters: [
    GradeReportSemester(
      label: _first,
      gpa: gpa,
      unitAttempted: 3,
      unitGained: 3,
      distinctions: ["Dean's List"],
      courses: const [
        GradeReportCourse(
          code: 'TEST1003',
          title: _title,
          unitAttempted: 3,
          unitGained: 3,
          grade: 'A-',
          gradePoint: 11.1,
          score: '87',
          remarkCode: '*',
        ),
      ],
    ),
    GradeReportSemester(
      label: _second,
      courses: const [
        GradeReportCourse(
          code: 'TEST2003',
          title: 'Synthetic research',
          unitAttempted: 3,
          unitGained: 3,
          grade: 'S',
          gradePoint: null,
          score: '',
          remarkCode: '',
        ),
      ],
    ),
  ],
);

class _Lease implements AppSessionLease {
  bool active = true;
  @override
  String get owner => 'synthetic-grades';
  @override
  bool get isActive => active;
}

class _Controller extends HomeNavigationFixture {
  _Lease lease = _Lease();
  GradeReport result = _report();
  GradeReport? cached;
  Object? failure;
  Completer<GradeReport>? gate;
  final calls = <bool>[];
  int listeners = 0;
  @override
  AppSessionLease? captureSessionLease() => lease.active ? lease : null;
  @override
  GradeReport? get cachedGradeReport => cached;
  @override
  Future<GradeReport> loadGradeReport({bool forceRefresh = false}) async {
    calls.add(forceRefresh);
    if (failure != null) throw failure!;
    return gate == null ? result : gate!.future;
  }

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  void changeAccount() {
    lease.active = false;
    lease = _Lease();
    cached = _report(gpa: 2.22);
    notifyListeners();
  }
}

class _CachedVisibilityService
    implements HomeCardVisibilityService, CachedHomeCardVisibilityService {
  final network = Completer<HomeCardVisibility>();

  @override
  Future<HomeCardVisibility?> loadCached() async => const HomeCardVisibility(
    version: 4,
    cards: {HomeServiceCard.gradeReport: false},
  );

  @override
  Future<HomeCardVisibility> load() => network.future;

  @override
  void dispose() {}
}

Future<void> _pump(
  WidgetTester tester,
  _Controller source, {
  double width = 390,
  Locale locale = const Locale('en'),
  bool settle = true,
  Widget? home,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: width == 900 ? AppTheme.dark : AppTheme.light,
      locale: locale,
      supportedLocales: BnbuLocalizations.supportedLocales,
      localizationsDelegates: const [
        BnbuLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.6 : 1)),
        child: child!,
      ),
      home: home ?? GradeReportPage(controller: source),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
    ]) {
      testWidgets(
        'native grades $width $locale with semester reflow and details',
        (tester) async {
          final source = _Controller();
          addTearDown(() {
            source.dispose();
            tester.view.reset();
          });
          await _pump(tester, source, width: width, locale: locale);
          expect(find.text('3.17'), findsNWidgets(2));
          expect(find.text("Dean's List"), findsOneWidget);
          expect(
            find.byKey(const ValueKey('grade-semester-sidebar')),
            width >= 880 ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('grade-semester-filter')),
            width < 880 ? findsOneWidget : findsNothing,
          );
          final courseTitle = find.text(_title);
          await tester.ensureVisible(courseTitle);
          await tester.pumpAndSettle();
          await tester.tap(courseTitle);
          await tester.pumpAndSettle();
          expect(find.text('11.1'), findsOneWidget);
          expect(find.text('87'), findsOneWidget);
          expect(find.text('*'), findsOneWidget);
          expect(source.calls, [false]);
          expect(tester.takeException(), isNull);
          if (width >= 880) {
            await tester.tap(
              find.byKey(const ValueKey('grade-semester-$_second')),
            );
          } else {
            await tester.tap(
              find.byKey(const ValueKey('grade-semester-filter')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(_second).last);
          }
          await tester.pumpAndSettle();
          await tester.drag(
            find.byKey(const ValueKey('grade-report-content')),
            const Offset(0, 1200),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('grade-section-$_first')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('grade-section-$_second')),
            findsOneWidget,
          );
          expect(find.text('—'), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('missing school GPA never derives GPA or honours', (
    tester,
  ) async {
    final source = _Controller()..result = _report(gpa: null);
    addTearDown(() {
      source.dispose();
      tester.view.reset();
    });
    await _pump(tester, source);
    expect(find.text('3.70'), findsNothing);
    expect(find.textContaining('Honours'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.text("Dean's List"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('initial loading then error and forced retry', (tester) async {
    final source = _Controller()..gate = Completer<GradeReport>();
    addTearDown(() {
      source.dispose();
      tester.view.reset();
    });
    await _pump(tester, source, settle: false);
    expect(find.byType(BnbuInitialLoading), findsOneWidget);
    source.gate!.completeError(StateError('private upstream error'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load grades. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private upstream'), findsNothing);
    source.gate = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(source.calls, [false, true]);
    expect(find.text('3.17'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'cached data survives failed pull refresh and unavailable result',
    (tester) async {
      final source = _Controller()
        ..cached = _report()
        ..gate = Completer<GradeReport>();
      addTearDown(() {
        source.dispose();
        tester.view.reset();
      });
      await _pump(tester, source, settle: false);
      expect(find.text('3.17'), findsNWidgets(2));
      expect(
        tester
            .widget<BnbuUpdateProgress>(find.byType(BnbuUpdateProgress))
            .active,
        isTrue,
      );
      source.gate!.complete(source.result);
      source.gate = null;
      await tester.pumpAndSettle();
      source.failure = StateError('offline');
      await tester.drag(
        find.byKey(const ValueKey('grade-report-content')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(source.calls, [false, true]);
      expect(find.text('3.17'), findsNWidgets(2));
      expect(
        find.text('Unable to load grades. Please try again.'),
        findsOneWidget,
      );
      source.failure = null;
      source.result = const GradeReport.unavailable();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        find.text('School grades are currently unavailable'),
        findsOneWidget,
      );
      expect(find.text('3.17'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final availability in [
    GradeReportAvailability.empty,
    GradeReportAvailability.unavailable,
  ]) {
    testWidgets('distinct $availability state', (tester) async {
      final source = _Controller()
        ..result = GradeReport(
          availability: availability,
          semesters: [],
          academicYears: [],
        );
      addTearDown(() {
        source.dispose();
        tester.view.reset();
      });
      await _pump(tester, source);
      expect(
        find.text(
          availability == GradeReportAvailability.empty
              ? 'No grades available'
              : 'School grades are currently unavailable',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('grade-cumulative-summary')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'account change clears data and rejects late completion and retry',
    (tester) async {
      final source = _Controller()
        ..cached = _report()
        ..gate = Completer<GradeReport>();
      addTearDown(() {
        source.dispose();
        tester.view.reset();
      });
      await _pump(tester, source, settle: false);
      source.changeAccount();
      await tester.pumpAndSettle();
      expect(find.text('3.17'), findsNothing);
      expect(
        find.text('Your sign-in session has changed. Open GPA again.'),
        findsOneWidget,
      );
      source.gate!.complete(_report(gpa: 3.99));
      await tester.pumpAndSettle();
      expect(find.text('3.99'), findsNothing);
      expect(find.text('2.22'), findsNothing);
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(source.calls, [false]);
      await tester.pumpWidget(const SizedBox());
      expect(source.listeners, 0);
    },
  );

  testWidgets('invalid initial lease never reads cache or loads', (
    tester,
  ) async {
    final source = _Controller()..cached = _report();
    source.lease.active = false;
    addTearDown(() {
      source.dispose();
      tester.view.reset();
    });
    await _pump(tester, source);
    expect(source.calls, isEmpty);
    expect(find.text('3.17'), findsNothing);
    expect(
      find.text('Your sign-in session has changed. Open GPA again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispose detaches listener and ignores pending completion', (
    tester,
  ) async {
    final source = _Controller()..gate = Completer<GradeReport>();
    addTearDown(() {
      source.dispose();
      tester.view.reset();
    });
    await _pump(tester, source, settle: false);
    expect(source.listeners, 1);
    await tester.pumpWidget(const SizedBox());
    expect(source.listeners, 0);
    source.gate!.complete(_report());
    source.changeAccount();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller replacement rejects the old pending response', (
    tester,
  ) async {
    final oldSource = _Controller()..gate = Completer<GradeReport>();
    final newSource = _Controller()..result = _report(gpa: 2.22);
    addTearDown(() {
      oldSource.dispose();
      newSource.dispose();
      tester.view.reset();
    });
    await _pump(tester, oldSource, settle: false);
    await _pump(tester, newSource);
    expect(oldSource.listeners, 0);
    expect(find.text('2.22'), findsNWidgets(2));
    oldSource.gate!.complete(_report(gpa: 3.99));
    await tester.pumpAndSettle();
    expect(find.text('3.99'), findsNothing);
    expect(find.text('2.22'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    expect(newSource.listeners, 0);
  });

  testWidgets('cached hidden GPA never flashes before network refresh', (
    tester,
  ) async {
    final source = _Controller();
    final service = _CachedVisibilityService();
    addTearDown(() {
      source.dispose();
      tester.view.reset();
    });
    await _pump(
      tester,
      source,
      settle: false,
      home: HomePage(
        controller: source,
        onGoToIspace: () {},
        onGoToSchedule: () {},
        onGoToUser: () {},
        homeCardVisibilityService: service,
      ),
    );
    expect(find.byKey(const ValueKey('home-quick-action-绩点')), findsNothing);
    await tester.pump();
    expect(find.byKey(const ValueKey('home-quick-action-绩点')), findsNothing);
    expect(service.network.isCompleted, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets(
      'home GPA entry uses content navigation and never prefetches $width',
      (tester) async {
        final source = _Controller();
        final shell = RootShellController();
        final mail = MailAssistantIntentController();
        final ta = TaCourseController(sessionController: source);
        addTearDown(() {
          ta.dispose();
          mail.dispose();
          shell.dispose();
          source.dispose();
          tester.view.reset();
        });
        await _pump(
          tester,
          source,
          width: width,
          home: RootShellPage(
            controller: source,
            shellController: shell,
            taCourseController: ta,
            mailIntentController: mail,
            pageOverrideBuilder: (tab) => tab == AppTab.home
                ? HomePage(
                    controller: source,
                    onGoToIspace: () {},
                    onGoToSchedule: () {},
                    onGoToUser: () {},
                    homeCardVisibilityService:
                        const DefaultHomeCardVisibilityService(),
                  )
                : const SizedBox(),
          ),
        );
        expect(source.calls, isEmpty);
        final tile = find.byKey(const ValueKey('home-quick-action-绩点'));
        await tester.ensureVisible(tile);
        final entries = tester
            .widgetList<Material>(
              find.descendant(
                of: find.byKey(const ValueKey('home-quick-access-panel')),
                matching: find.byType(Material),
              ),
            )
            .map((entry) => entry.key)
            .toList();
        final gradeIndex = entries.indexOf(
          const ValueKey('home-quick-action-绩点'),
        );
        expect(entries[gradeIndex - 1], const ValueKey('home-quick-action-校历'));
        expect(
          entries[gradeIndex + 1],
          const ValueKey('home-quick-action-请假申请'),
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(GradeReportPage), findsOneWidget);
        expect(source.calls, [false]);
        expect(
          find.byKey(const ValueKey('root-bottom-navigation')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('root-side-navigation-panel')),
          width >= 700 ? findsOneWidget : findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(GradeReportPage), findsNothing);
        expect(
          find.byKey(const ValueKey('root-bottom-navigation')),
          width < 700 ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
