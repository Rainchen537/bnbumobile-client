import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple widget offers overview, schedule, and DDL choices', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('case overview'));
    expect(source, contains('case schedule'));
    expect(source, contains('case deadlines'));
    expect(source, isNot(contains('case nextClass')));
    expect(source, isNot(contains('case scheduleList')));
    expect(source, isNot(contains('case scheduleGrid')));
    expect(source, contains('.overview: "概况"'));
    expect(source, contains('.schedule: "课表"'));
    expect(source, contains('.deadlines: "DDL"'));
    expect(source, contains('if let course = nextCourse'));
    expect(source, contains('if let deadline = upcomingDeadlines.first'));
    expect(source, contains('选择概况时同时显示课程与 DDL'));
    expect(source, contains('alignment: .topLeading'));
  });

  test('widget content uses text without decorative side icons', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, isNot(contains('Image(systemName:')));
    expect(source, isNot(contains('systemImage:')));
    expect(source, isNot(contains('Circle()')));
    expect(source, isNot(contains('"sparkles"')));
    expect(source, isNot(contains('"calendar.badge.checkmark"')));
    expect(source, isNot(contains('"checkmark.circle"')));
  });

  test('standalone DDL entries reuse the overview card treatment', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('private func deadlineSummary'));
    expect(source, contains('private func deadlineRow'));
    expect(source, contains('private func deadlineCard'));
    expect(source, contains('detail: deadlineLabel(deadline.dueAt)'));
    expect(
      source,
      contains('detail: [deadline.courseName, deadlineDate(deadline.dueAt)]'),
    );
    expect(source, contains('.padding(.horizontal, 8)'));
    expect(source, contains('.padding(.vertical, 4)'));
    expect(
      source,
      contains(
        '.background(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.10))',
      ),
    );
    expect(source, contains('.fill(Color.orange)'));
    expect(source, contains('.frame(width: 4)'));
  });

  test('iPhone only exposes layout choice for large widget families', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('enum BnbuWidgetScheduleLayout'));
    expect(source, contains('case horizontal'));
    expect(source, contains('case vertical'));
    expect(source, contains('.horizontal: "课表横版"'));
    expect(source, contains('.vertical: "课表纵版"'));
    expect(source, contains('@Parameter(title: "课表样式", default: .horizontal)'));
    expect(source, contains('Switch(.widgetFamily)'));
    expect(source, contains('Case([.systemLarge, .systemExtraLarge])'));
    expect(
      source,
      contains(r'Summary("显示 \(\.$content)，使用 \(\.$scheduleLayout)")'),
    );
    expect(source, contains('DefaultCase'));
    expect(source, contains(r'Summary("显示 \(\.$content)")'));
    expect(source, isNot(contains('BnbuCampusLargeWidget')));
    expect(source, isNot(contains('BnbuLargeWidgetConfigurationIntent')));
    expect(source, isNot(contains('largeWidgetKind')));
    expect(
      source,
      contains(
        '.supportedFamilies([.systemSmall, .systemMedium, '
        '.systemLarge, .systemExtraLarge])',
      ),
    );
  });

  test(
    'macOS widget uses a legacy editable intent with the published identity',
    () {
      final source = File(
        'apple/BnbuWidgets/BnbuWidget.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final intentDefinition = File(
        'apple/BnbuWidgets/BnbuMacWidget.intentdefinition',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        source,
        contains(
          'struct BnbuWidgetConfigurationIntent: '
          'WidgetConfigurationIntent',
        ),
      );
      expect(source, isNot(contains('BnbuMacWidgetConfigurationIntent')));
      expect(
        RegExp(
          r'struct BnbuWidgetConfigurationIntent: WidgetConfigurationIntent',
        ).allMatches(source),
        hasLength(1),
      );
      expect(
        RegExp(r'@Parameter\(title: "显示内容"').allMatches(source),
        hasLength(1),
      );
      expect(
        RegExp(r'@Parameter\(title: "课表样式"').allMatches(source),
        hasLength(1),
      );
      expect(source, contains('private let widgetKind = "BnbuCampusWidget"'));
      expect(source, isNot(contains('BnbuCampusWidgetMac')));
      expect(source, contains('intent: BnbuWidgetConfigurationIntent.self'));
      expect(
        source,
        contains(
          'private struct BnbuMacWidgetProvider: IntentTimelineProvider',
        ),
      );
      expect(source, contains('return IntentConfiguration('));
      expect(source, contains('return AppIntentConfiguration('));
      expect(source, contains('private struct BnbuWidgetSelection'));
      expect(source, contains('switch entry.configuration.content'));
      expect(source, contains('switch entry.configuration.scheduleLayout'));
      expect(
        intentDefinition,
        contains('<string>BnbuWidgetConfiguration</string>'),
      );
      expect(intentDefinition, contains('<string>BNBU.ME · Mac 小组件</string>'));
      expect(intentDefinition, contains('<string>content</string>'));
      expect(intentDefinition, contains('<string>scheduleLayout</string>'));
      expect(intentDefinition, contains('<string>概况</string>'));
      expect(intentDefinition, contains('<string>课表</string>'));
      expect(intentDefinition, contains('<string>DDL</string>'));
      expect(intentDefinition, contains('<string>课表横版</string>'));
      expect(intentDefinition, contains('<string>课表纵版</string>'));
    },
  );

  test('large horizontal schedule shows the full week on a time grid', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('if usesWeeklySchedule'));
    expect(
      source,
      contains('family == .systemLarge || family == .systemExtraLarge'),
    );
    expect(
      source,
      contains('case .horizontal:\n      weeklyTimetableSchedule'),
    );
    expect(source, contains('private var weeklyTimetableSchedule'));
    expect(source, contains(r'ForEach(displayedWeekDates, id: \.self)'));
    expect(source, contains('GeometryReader { geometry in'));
    expect(source, contains('weeklyTimelineGrid(size: geometry.size)'));
    expect(source, contains('private func weeklyTimelineGrid(size: CGSize)'));
    expect(source, contains('.strokeBorder('));
    expect(source, contains('private var weekCourses'));
    expect(source, contains('private var campusWeekStart'));
    expect(
      source,
      contains('header(interfaceLanguage.text("本周课表", "本週課表", "This Week"))'),
    );
    expect(source, isNot(contains('weeklyHorizontalTimeRow')));
    expect(source, isNot(contains('weeklyHorizontalTimeCell')));
  });

  test('weekly timeline scales classes and compresses long empty gaps', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('private var weeklyTimelineGridStartMinutes'));
    expect(source, contains('private var weeklyTimelineGridEndMinutes'));
    expect(source, contains('private var weeklyTimelineMarks'));
    expect(source, contains('private var weeklyTimelineOccupiedRanges'));
    expect(source, contains('private var weeklyTimelineSegments'));
    expect(source, contains('private func weeklyTimelineDisplayOffset'));
    expect(source, contains('private func weeklyTimelineGridY'));
    expect(
      source,
      contains('let courseStart = campusMinutes(course.startsAt)'),
    );
    expect(source, contains('let courseEnd = max(courseStart + 1'));
    expect(source, contains('courseBottom - courseY'));
    expect(source, contains('weeklyTimelineMinimumCourseHeight'));
    expect(source, contains('family == .systemExtraLarge ? 30 : 28'));
    expect(source, contains('family == .systemExtraLarge ? 45 : 30'));
    expect(source, contains('family == .systemExtraLarge ? 7.125 : 6.75'));
    expect(source, contains('family == .systemExtraLarge ? 10.2 : 9.6'));
    expect(source, contains('family == .systemExtraLarge ? 30 : 26'));
    expect(source, contains('private var weeklyTimelineDaySpacing'));
    expect(
      source,
      contains('let titleLineLimit = availableHeight >= 34 ? 2 : 1'),
    );
    expect(source, contains('let showsRoom = !course.room.isEmpty'));
    expect(source, contains('.layoutPriority(2)'));
    expect(source, contains('availableHeight: courseHeight'));
    expect(
      source,
      contains(
        '.frame(width: size.width, height: size.height, '
        'alignment: .topLeading)',
      ),
    );
    expect(source, isNot(contains('.minimumScaleFactor(0.85)')));
    final courseBlockStart = source.indexOf(
      'private func weeklyTimelineCourseBlock',
    );
    final courseBlockEnd = source.indexOf(
      'private var todayVerticalSchedule',
      courseBlockStart,
    );
    final courseBlock = source.substring(courseBlockStart, courseBlockEnd);
    expect(courseBlock, contains('Rectangle()'));
    expect(courseBlock, isNot(contains('RoundedRectangle')));
    expect(source, contains('width: dayWidth'));
    expect(source, contains('.offset(x: columnX, y: courseY)'));
    expect(source, contains('ForEach(courses(on: date))'));
  });

  test('large vertical schedule shows today courses only', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('case .vertical:\n      todayVerticalSchedule'));
    expect(source, contains('private var todayVerticalSchedule'));
    expect(
      source,
      contains(r'ForEach(Array(todayCourses.enumerated()), id: \.element.id)'),
    );
    expect(source, contains('todayVerticalTimeSpacing'));
    expect(source, contains('todayVerticalCourseRow'));
    expect(
      source,
      contains('current.startsAt.timeIntervalSince(previous.endsAt)'),
    );
    expect(
      source,
      contains(
        'Text("\\(shortTime(course.startsAt))–\\(shortTime(course.endsAt))")',
      ),
    );
    expect(source, isNot(contains('weeklyVerticalSchedule')));
    expect(source, isNot(contains('nonEmptyWeekDates')));
    expect(source, contains('lightAccentHex'));
    expect(source, contains('darkAccentHex'));
    expect(source, contains('@Environment(\\.colorScheme)'));
    expect(source, contains('courseAccentColor(course)'));
    expect(source, contains('family == .systemExtraLarge ? 16 : 14'));
    final verticalStart = source.indexOf('private func todayVerticalCourseRow');
    final verticalEnd = source.indexOf(
      'private func compactScheduleRow',
      verticalStart,
    );
    final verticalSource = source.substring(verticalStart, verticalEnd);
    expect(verticalSource, isNot(contains('下一节课')));
  });

  test('smaller schedule families hide courses that have ended', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('private var dailySchedule'));
    expect(source, contains('private var todayCourses'));
    expect(source, contains('private var remainingTodayCourses'));
    expect(source, contains('campusCalendar.isDate'));
    expect(source, contains(r'todayCourses.filter { $0.endsAt > entry.date }'));
    expect(
      source,
      contains(
        'ForEach(Array(remainingTodayCourses.prefix(scheduleRowLimit)))',
      ),
    );
    expect(source, contains('remainingTodayCourses.count - scheduleRowLimit'));
    expect(source, contains('"今天没有课程"'));
    expect(source, contains('"今天课程已结束"'));
    expect(source, contains('compactScheduleRow(course)'));

    final verticalStart = source.indexOf('private var todayVerticalSchedule');
    final verticalEnd = source.indexOf(
      'private func todayVerticalCourseRow',
      verticalStart,
    );
    final verticalSource = source.substring(verticalStart, verticalEnd);
    expect(verticalSource, contains('todayCourses'));
    expect(verticalSource, isNot(contains('remainingTodayCourses')));
  });

  test('smaller schedule refreshes when the next course ends', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('context.family == .systemSmall'));
    expect(source, contains('context.family == .systemMedium'));
    expect(source, contains('.map(\\.endsAt)'));
    expect(source, contains(r'.filter({ $0 > now })'));
    expect(source, contains('min(regularRefreshDate, nextCourseEnd)'));
    expect(source, contains('policy: .after(refreshDate)'));
  });

  test('widget rendering follows the language stored in the app snapshot', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('enum WidgetInterfaceLanguage'));
    expect(source, contains('case simplifiedChinese = "zh-Hans"'));
    expect(source, contains('case traditionalChinese = "zh-Hant"'));
    expect(source, contains('case english = "en"'));
    expect(source, contains('let interfaceLanguage: String?'));
    expect(source, contains('entry.snapshot.resolvedInterfaceLanguage'));
    expect(source, contains('"今日概览", "今日概覽", "Today\'s Overview"'));
    expect(source, contains('"本周课表", "本週課表", "This Week"'));
    expect(source, contains('"今天没有课程"'));
    expect(source, contains('"今天沒有課程"'));
    expect(source, contains('"No classes today"'));
    expect(
      source,
      contains(
        'formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)',
      ),
    );
  });

  test('iPhone widget taps follow the configured widget content', () {
    final widget = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final bridge = File(
      'ios/Runner/BnbuAppNavigationBridge.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      widget,
      contains('widgetDestinationURL(for content: BnbuWidgetContent)'),
    );
    expect(widget, contains('case .overview:\n    destination = "home"'));
    expect(widget, contains('case .deadlines:\n    destination = "ispace"'));
    expect(widget, contains('case .schedule:\n    destination = "schedule"'));
    expect(widget, contains('components.host = "widget"'));
    expect(
      widget,
      contains(
        '.widgetURL(widgetDestinationURL(for: entry.configuration.content))',
      ),
    );
    expect(
      bridge,
      contains('supportedSources = Set(["live-activity", "widget"])'),
    );
    expect(bridge, contains('supportedSources.contains(source)'));
  });

  test('macOS widget opens the matching page in the local Mac app', () {
    final source = File(
      'apple/BnbuWidgets/BnbuWidget.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final macInfo = File(
      'macos/Runner/Info.plist',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final appDelegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final mainWindow = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final intentDefinition = File(
      'apple/BnbuWidgets/BnbuMacWidget.intentdefinition',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('BNBU.ME · Mac'));
    expect(source, contains('BNBU.ME · iPhone'));
    expect(source, contains('private let widgetKind = "BnbuCampusWidget"'));
    expect(source, isNot(contains('BnbuCampusWidgetMac')));
    expect(source, contains('kind: widgetKind'));
    expect(intentDefinition, contains('<string>BNBU.ME · Mac 小组件</string>'));
    expect(
      source,
      contains(
        'static var title: LocalizedStringResource = '
        '"BNBU.ME · iPhone 小组件"',
      ),
    );
    expect(source, contains('forInfoDictionaryKey: "BnbuAppURLScheme"'));
    expect(source, isNot(contains('scheme = "handsbnbu-mac"')));
    expect(source, contains('case .overview:\n    destination = "home"'));
    expect(source, contains('case .deadlines:\n    destination = "ispace"'));
    expect(source, contains('case .schedule:\n    destination = "schedule"'));
    expect(source, contains('.description("")'));
    expect(source, isNot(contains('课表与 DDL 可分开显示')));
    expect(
      source,
      contains(
        '.widgetURL(widgetDestinationURL(for: entry.configuration.content))',
      ),
    );
    expect(
      macInfo,
      contains(r'<string>$(BNBU_MACOS_APP_BUNDLE_IDENTIFIER)</string>'),
    );
    for (final lane in ['development', 'release']) {
      expect(
        File('macos/Flutter/Signing.$lane.xcconfig').readAsStringSync(),
        contains(
          r'BNBU_IOS_APP_URL_SCHEME = $(BNBU_MACOS_APP_BUNDLE_IDENTIFIER)',
        ),
      );
    }
    expect(macInfo, contains('<key>BnbuAppURLScheme</key>'));
    expect(appDelegate, contains('supportedSources = Set(["widget"])'));
    expect(
      appDelegate,
      contains('BnbuAppNavigationBridge.shared.handle(url: url)'),
    );
    expect(mainWindow, contains('BnbuAppNavigationBridge.shared.configure('));
  });

  test('widget gallery labels iPhone and Mac sources separately', () {
    final widgetInfo = File(
      'apple/BnbuWidgets/Info.plist',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final macProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(widgetInfo, contains(r'$(BNBU_WIDGET_DISPLAY_NAME)'));
    expect(
      'BNBU_WIDGET_DISPLAY_NAME = "BNBU.ME · iPhone";'.allMatches(iosProject),
      hasLength(3),
    );
    expect(
      'BNBU_WIDGET_DISPLAY_NAME = "BNBU.ME · Mac";'.allMatches(macProject),
      hasLength(3),
    );
  });
}
