import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS runner enables and synchronizes Live Activities', () {
    final info = File(
      'ios/Runner/Info.plist',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final delegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final manager = File(
      'ios/Runner/BnbuLiveActivityManager.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(info, contains('<key>NSSupportsLiveActivities</key>'));
    expect(delegate, contains('synchronize(snapshotJSON: payload)'));
    expect(delegate, contains('BnbuLiveActivityManager.shared.clear()'));
    expect(delegate, contains('synchronizeLiveActivityFromCachedSnapshot()'));
    expect(manager, contains('let preferences = snapshot.liveActivity'));
    expect(manager, contains('guard preferences.enabled else'));
    expect(manager, contains('classLeadMinutes: 15'));
    expect(manager, contains('courseDismissAfterStartMinutes: 5'));
    expect(manager, contains('deadlineLeadMinutes: 720'));
    expect(manager, contains('courseEnabled: true'));
    expect(manager, contains('deadlineEnabled: false'));
    expect(manager, contains('preferences.classLeadTime'));
    expect(manager, contains('preferences.courseDismissAfterStartTime'));
    expect(manager, contains('preferences.deadlineLeadTime'));
    expect(
      manager,
      contains(
        'preferences.courseEnabled != false && preferences.classLeadMinutes > 0',
      ),
    );
    expect(manager, contains('min(max(classLeadMinutes, 5), 120)'));
    expect(
      manager,
      contains('min(max(courseDismissAfterStartMinutes ?? 5, 0), 20)'),
    );
    expect(
      manager,
      contains(
        'preferences.deadlineEnabled != false && preferences.deadlineLeadMinutes > 0',
      ),
    );
    expect(manager, contains('max(deadlineLeadMinutes, 30)'));
    expect(
      manager,
      contains('ActivityAuthorizationInfo().areActivitiesEnabled'),
    );
    expect(manager, contains('Activity.request('));
    expect(manager, contains('await matching.update(candidate.content)'));
    expect(manager, contains('staleDate: dismissAt'));
    expect(manager, contains('scheduleDismissal(for: matching'));
    expect(manager, contains('dismissalTask = Task'));
    expect(
      manager,
      contains('await current.end(nil, dismissalPolicy: .immediate)'),
    );
    expect(
      manager,
      contains('await activity.end(nil, dismissalPolicy: .immediate)'),
    );
  });

  test(
    'Dynamic Island uses the app icon, bounded DDL layout and event-specific content',
    () {
      final source = File(
        'apple/BnbuWidgets/BnbuLiveActivityWidget.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final bundle = File(
        'apple/BnbuWidgets/BnbuWidget.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(source, contains('ActivityConfiguration(for:'));
      expect(source, contains('DynamicIslandExpandedRegion(.leading)'));
      expect(source, contains('DynamicIslandExpandedRegion(.trailing)'));
      expect(
        source,
        contains('DynamicIslandExpandedRegion(.bottom, priority: 3)'),
      );
      expect(source, contains('.padding(.leading, 10)'));
      expect(source, contains('.padding(.trailing, 10)'));
      expect(source, contains('compactLeading:'));
      expect(source, contains('compactTrailing:'));
      expect(source, contains('minimal:'));
      expect(source, isNot(contains('Text("BNBUMe")')));
      expect(source, contains('BnbuLiveActivityAppIcon'));
      expect(source, contains('AppIcon60x60@2x.png'));
      expect(source, contains('BnbuLiveActivityDeadlineLeading'));
      expect(source, contains('BnbuLiveActivityDeadlineBadge'));
      expect(source, contains('Text("DDL")'));
      expect(source, isNot(contains('exclamationmark.circle')));
      expect(source, contains('BnbuLiveActivityEventTime'));
      expect(source, contains('BnbuLiveActivityExpandedDetail'));
      expect(source, contains('BnbuLiveActivityDeadlineExpandedContent'));
      expect(source, contains('BnbuLiveActivityDeadlineRemaining'));
      // Structural guard only; system rendering is checked with the native fixture host.
      expect(source, contains('ViewThatFits(in: .vertical)'));
      expect(source, contains('content(compact: false, bounded: false)'));
      expect(source, contains('content(compact: true, bounded: false)'));
      expect(source, contains('content(compact: true, bounded: true)'));
      expect(source, contains('.frame(maxHeight: 96, alignment: .topLeading)'));
      expect(
        source,
        contains('.frame(maxHeight: 128, alignment: .topLeading)'),
      );
      expect(
        source,
        contains(
          '.activityBackgroundTint(colorScheme == .dark ? .black : .white)',
        ),
      );
      expect(source, isNot(contains('minHeight:')));
      expect(source, contains('.lineLimit(nil)'));
      expect(source, contains('.font(.headline)'));
      expect(source, contains('BnbuLiveActivityCourseLeading'));
      expect(source, contains('context.state.location'));
      expect(source, contains('courseTimeRange(context: context)'));
      expect(source, contains('.lineLimit(compact ? 1 : 2)'));
      expect(source, contains('.fixedSize(horizontal: false, vertical: true)'));
      expect(source, isNot(contains('.truncationMode(.tail)')));
      expect(source, contains('.fixedSize(horizontal: true, vertical: false)'));
      expect(source, contains('.accessibilityLabel("BNBU.ME")'));
      expect(source, isNot(contains('"下一节课"')));
      expect(source, isNot(contains('"正在上课"')));
      expect(source, contains('Text(context.state.title)'));
      expect(source, isNot(contains('"DDL 即将到期"')));
      expect(source, isNot(contains('TimelineView(.periodic')));
      expect(source, contains('format: .timer('));
      expect(source, contains('maxPrecision: .seconds(60)'));
      expect(source, contains('Text(context.state.eventAt, style: .relative)'));
      expect(source, contains('Text("已截止")'));
      expect(source, isNot(contains('timerInterval:')));
      expect(source, contains('.padding(.bottom, 8)'));
      expect(
        source,
        isNot(contains('.contentMargins(.vertical, 0, for: .expanded)')),
      );
      expect(source, contains('Text(context.state.detail)'));
      expect(source, contains('systemImage: "mappin.and.ellipse"'));
      expect(source, contains('timeZoneID: context.attributes.campusTimeZone'));
      expect(bundle, contains('BnbuLiveActivityWidget()'));

      final expandedRegions = RegExp(
        r'DynamicIslandExpandedRegion\(\.bottom, priority: 3\)[\s\S]*?'
        r'} compactLeading:',
      ).firstMatch(source)!.group(0)!;
      expect(
        expandedRegions,
        contains('BnbuLiveActivityDeadlineExpandedContent(context: context)'),
      );

      final lockScreenDeadline = RegExp(
        r'private var deadlineContent: some View \{[\s\S]*?'
        r'\n  \}\n\}',
      ).firstMatch(source)!.group(0)!;
      expect(lockScreenDeadline, isNot(contains('calendar.badge.clock')));
      expect(
        lockScreenDeadline,
        isNot(contains('HStack(alignment: .top, spacing: 8)')),
      );
      expect(
        lockScreenDeadline,
        contains('VStack(alignment: .leading, spacing: 4)'),
      );
      expect(
        lockScreenDeadline,
        contains('.frame(maxWidth: .infinity, alignment: .leading)'),
      );
      expect(lockScreenDeadline, contains('Text(context.state.title)'));
      expect(lockScreenDeadline, contains('.lineLimit(bounded ? 4 : nil)'));
      expect(
        lockScreenDeadline,
        contains('.fixedSize(horizontal: false, vertical: true)'),
      );
    },
  );

  test('consecutive blocks of the same course are merged before alerting', () {
    final manager = File(
      'ios/Runner/BnbuLiveActivityManager.swift',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(manager, contains('maximumCourseMergeGap: TimeInterval = 15 * 60'));
    expect(manager, contains('mergedCourses(snapshot.courses)'));
    expect(manager, contains('shouldMerge(previous, with: course)'));
    expect(manager, contains('normalized(previous.title)'));
    expect(manager, contains('normalized(previous.code)'));
    expect(manager, contains('normalized(previous.room)'));
    expect(manager, contains('endsAt: max(previous.endsAt, course.endsAt)'));
    expect(manager, contains('detail: ""'));
    expect(manager, contains('destination: "schedule"'));
    expect(manager, contains('destination: "ispace"'));
    expect(manager, contains('eventID: "course-layout-2|'));
    expect(manager, contains('eventID: "deadline-layout-5|'));
  });

  test(
    'Live Activity taps use isolated app routes for warm and cold starts',
    () {
      final attributes = File(
        'ios/Shared/BnbuLiveActivityAttributes.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final widget = File(
        'apple/BnbuWidgets/BnbuLiveActivityWidget.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final widgetInfo = File(
        'apple/BnbuWidgets/Info.plist',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final runnerInfo = File(
        'ios/Runner/Info.plist',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final bridge = File(
        'ios/Runner/BnbuAppNavigationBridge.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final scene = File(
        'ios/Runner/BnbuSceneDelegate.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final delegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final developmentSigning = File(
        'ios/Flutter/Signing.development.xcconfig',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final releaseSigning = File(
        'ios/Flutter/Signing.release.xcconfig',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(attributes, contains('let destination: String?'));
      expect(widget, contains('.widgetURL(liveActivityDestinationURL'));
      expect(widget, contains('context.state.destination ?? fallback'));
      expect(widgetInfo, contains('<key>BnbuAppURLScheme</key>'));
      expect(runnerInfo, contains('<key>CFBundleURLTypes</key>'));
      expect(runnerInfo, contains('<key>BnbuAppURLScheme</key>'));
      expect(
        runnerInfo,
        contains(r'<string>$(BNBU_IOS_APP_URL_SCHEME)</string>'),
      );
      expect(
        runnerInfo,
        contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'),
      );
      expect(runnerInfo, contains(r'$(PRODUCT_MODULE_NAME).BnbuSceneDelegate'));
      expect(bridge, contains('takePendingDestination'));
      expect(bridge, contains('supportedDestinations'));
      expect(scene, contains('connectionOptions.urlContexts'));
      expect(scene, contains('openURLContexts'));
      expect(delegate, contains('BnbuAppNavigationBridge.shared.configure'));
      expect(
        delegate,
        contains('BnbuAppNavigationBridge.shared.handle(url: url)'),
      );
      expect(
        developmentSigning,
        contains(
          r'BNBU_IOS_APP_URL_SCHEME = $(BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER)',
        ),
      );
      expect(
        releaseSigning,
        contains(
          r'BNBU_IOS_APP_URL_SCHEME = $(BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER)',
        ),
      );
    },
  );

  test('Runner Profile uses the same development lane as iPhone widget', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    const marker = '249021D4217E4FDB00AE95B9 /* Profile */ = {';
    final start = project.indexOf(marker);
    expect(start, greaterThanOrEqualTo(0));
    final end = project.indexOf('\n\t\t};', start);
    expect(end, greaterThan(start));

    final runnerProfileConfiguration = project.substring(start, end);
    expect(runnerProfileConfiguration, contains('/* Profile.xcconfig */'));
    expect(
      runnerProfileConfiguration,
      isNot(contains('/* Release.xcconfig */')),
    );
  });

  test('Live Activity sources belong to the Runner and widget targets', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      RegExp(
        'BnbuLiveActivityAttributes\\.swift in Sources',
      ).allMatches(project),
      hasLength(4),
    );
    expect(project, contains('BnbuLiveActivityManager.swift in Sources'));
    expect(project, contains('BnbuAppNavigationBridge.swift in Sources'));
    expect(project, contains('BnbuSceneDelegate.swift in Sources'));
    expect(project, contains('BnbuLiveActivityWidget.swift in Sources'));
    expect(project, contains('ActivityKit.framework in Frameworks'));
  });
}
