import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watch app provides overview, weekly schedule, and DDL pages', () {
    final app = File(
      'apple/BnbuWatchApp/BnbuWatchApp.swift',
    ).readAsStringSync();
    final source = File(
      'apple/BnbuWatchApp/WatchRootView.swift',
    ).readAsStringSync();

    expect(app, contains('@main'));
    expect(source, contains('WatchOverviewView'));
    expect(source, contains('WatchWeekScheduleView'));
    expect(source, contains('WatchDeadlineListView'));
    expect(source, contains('WatchSettingsView'));
    expect(source, contains('.tabViewStyle(.verticalPage)'));
    expect(source, contains('ScrollView(.horizontal)'));
    expect(source, contains('WatchCampusCalendar.twoWeekDays'));
    expect(source, contains('(0..<14).compactMap'));
    expect(source, contains('ForEach(weekDays'));
    expect(
      source,
      contains('language.text("两周课表", "兩週課表", "Two-Week Timetable")'),
    );
    expect(source, contains('@State private var visibleDay: Date?'));
    expect(source, contains('inSameDayAs: now'));
    expect(
      source,
      contains('.scrollPosition(id: \$visibleDay, anchor: .center)'),
    );
    expect(source, contains('if !isShowingToday'));
    expect(source, contains('private var isShowingToday: Bool'));
    expect(source, contains('language.text("今日", "今日", "Today")'));
    expect(source, contains('visibleDay = today'));
    expect(source, contains('language.text("回到今日", "回到今日", "Back to today")'));
    expect(source, contains('.tabViewStyle(.verticalPage)'));
    expect(source, isNot(contains('.digitalCrownRotation(')));
    expect(source, isNot(contains('crownPageStep')));
    expect(source, isNot(contains('movePage(newStep > 0 ? 1 : -1)')));
    expect(source, isNot(contains('visibleDay = weekDays[newIndex]')));
    expect(source, contains('WatchCourseCard(course: course)'));
    expect(source, contains('if let teacher = course.teacher'));
    expect(source, isNot(contains('StudentEcard')));
    expect(source, isNot(contains('"eCard"')));
    expect(source, isNot(contains('校园卡')));
  });

  test('watch settings persist, hide, and reorder the three primary pages', () {
    final source = File(
      'apple/BnbuWatchApp/WatchRootView.swift',
    ).readAsStringSync();

    expect(source, contains('@AppStorage("bnbu.watch.selectedPage.v2")'));
    expect(source, contains('@AppStorage("bnbu.watch.pageOrder.v1")'));
    expect(source, contains('@AppStorage("bnbu.watch.hiddenPages.v1")'));
    expect(source, contains('WatchPrimaryPage.normalizedOrder'));
    expect(source, contains('WatchPrimaryPage.hiddenPages'));
    expect(source, contains('.filter { !hiddenPages.contains(\$0) }'));
    expect(source, contains('ForEach(Array(pages.enumerated())'));
    expect(source, contains('reordered.swapAt(index, destination)'));
    expect(source, contains('WatchPrimaryPage.encodedOrder(reordered)'));
    expect(source, contains('WatchPrimaryPage.encodedHiddenPages(updated)'));
    expect(source, contains('.tag("settings")'));
    expect(source, contains('isHidden ? "eye.slash" : "eye"'));
    expect(source, contains('"Show \\(page.title(language))"'));
    expect(source, contains('"Move \\(page.title(language)) up"'));
    expect(source, contains('"Move \\(page.title(language)) down"'));
  });

  test(
    'watch interface language follows the effective iPhone app language',
    () {
      final view = File(
        'apple/BnbuWatchApp/WatchRootView.swift',
      ).readAsStringSync();
      final store = File(
        'apple/BnbuWatchApp/WatchSnapshotStore.swift',
      ).readAsStringSync();
      final snapshot = File(
        'lib/models/widget_snapshot.dart',
      ).readAsStringSync();
      final coordinator = File(
        'lib/services/widget_snapshot_service.dart',
      ).readAsStringSync();

      expect(snapshot, contains("'interfaceLanguage': interfaceLanguage"));
      expect(coordinator, contains('resolveInterfaceLanguageTag'));
      expect(store, contains('let interfaceLanguage: String?'));
      expect(store, contains('enum WatchInterfaceLanguage'));
      expect(store, contains('Locale.preferredLanguages.first'));
      expect(store, contains('@Published private(set) var interfaceLanguage'));
      expect(store, contains('cachedInterfaceLanguageKey'));
      expect(store, contains('sessionReachabilityDidChange'));
      expect(view, contains('.environment(\\.watchInterfaceLanguage'));
      expect(view, contains('.id(store.interfaceLanguage.rawValue)'));
      expect(view, contains('"Overview"'));
      expect(view, contains('"兩週課表"'));

      final manager = File(
        'ios/Runner/BnbuWatchConnectivityManager.swift',
      ).readAsStringSync();
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(manager, contains('func updateInterfaceLanguage'));
      expect(manager, contains('updateApplicationContext(context)'));
      expect(manager, contains('session.sendMessage(context'));
      expect(manager, contains('sessionReachabilityDidChange'));
      expect(delegate, contains('updateWatchInterfaceLanguage'));
    },
  );

  test(
    'watch login is confirmed on iPhone and credentials are never synced',
    () {
      final view = File(
        'apple/BnbuWatchApp/WatchRootView.swift',
      ).readAsStringSync();
      final store = File(
        'apple/BnbuWatchApp/WatchSnapshotStore.swift',
      ).readAsStringSync();
      final manager = File(
        'ios/Runner/BnbuWatchConnectivityManager.swift',
      ).readAsStringSync();
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

      expect(view, contains('请先在 iPhone App 登录并同步'));
      expect(view, isNot(contains('SecureField')));
      expect(view, isNot(contains('TextField')));
      expect(store, contains('WCSession.default'));
      expect(store, contains('receivedApplicationContext'));
      expect(manager, contains('updateApplicationContext'));
      expect(manager, contains('requestSnapshot'));
      expect(delegate, contains('BnbuWatchConnectivityManager.shared.update'));
      expect(delegate, contains('BnbuWatchConnectivityManager.shared.clear()'));

      final synchronizedSource = '$store\n$manager';
      expect(synchronizedSource, isNot(contains('password')));
      expect(synchronizedSource, isNot(contains('cookie')));
      expect(synchronizedSource, isNot(contains('token')));
      expect(synchronizedSource, isNot(contains('studentId')));
    },
  );

  test('Xcode embeds a separately signed companion watch target', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(project, contains('BnbuWatchApp.app in Embed Watch Content'));
    expect(project, contains('BnbuWatchConnectivityManager.swift in Sources'));
    expect(project, contains('WatchSnapshotStore.swift in Sources'));
    expect(project, contains('WatchRootView.swift in Sources'));
    expect(project, contains('SDKROOT = watchos'));
    expect(project, contains('WATCHOS_DEPLOYMENT_TARGET = 10.0'));
    expect(project, contains('8A770107B11B22C33D440001 /* Assets.xcassets */'));
    expect(
      project,
      contains('8A770008B11B22C33D440001 /* Assets.xcassets in Resources */'),
    );
    expect(project, contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'));
    expect(
      project,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = '
        '"\$(BNBU_IOS_DEVELOPMENT_WATCH_BUNDLE_IDENTIFIER)";',
      ),
    );
    expect(
      project,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = '
        '"\$(BNBU_IOS_RELEASE_WATCH_BUNDLE_IDENTIFIER)";',
      ),
    );
    expect(
      project,
      contains(
        'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = '
        '"\$(BNBU_IOS_DEVELOPMENT_BUNDLE_IDENTIFIER)";',
      ),
    );
    expect(
      project,
      contains(
        'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = '
        '"\$(BNBU_IOS_RELEASE_BUNDLE_IDENTIFIER)";',
      ),
    );

    for (final configurationId in <String>[
      '8A770501B11B22C33D440001',
      '8A770502B11B22C33D440001',
      '8A770503B11B22C33D440001',
    ]) {
      final start = project.indexOf('$configurationId /*');
      final end = project.indexOf('\n\t\t};', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final configuration = project.substring(start, end);
      expect(configuration, contains('SDKROOT = watchos;'));
      expect(configuration, contains('FRAMEWORK_SEARCH_PATHS = "";'));
      expect(configuration, contains('HEADER_SEARCH_PATHS = "";'));
      expect(configuration, contains('LIBRARY_SEARCH_PATHS = "";'));
      expect(configuration, contains('OTHER_LDFLAGS = "";'));
      expect(configuration, contains('OTHER_MODULE_VERIFIER_FLAGS = "";'));
    }
  });

  test('watch app icon reuses the phone app master artwork', () {
    final phoneIcon = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    ).readAsBytesSync();
    final watchIcon = File(
      'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/'
      'Icon-Watch-1024x1024@1x.png',
    ).readAsBytesSync();
    final contents = File(
      'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Contents.json',
    ).readAsStringSync();

    expect(watchIcon, orderedEquals(phoneIcon));
    expect(contents, contains('Icon-Watch-1024x1024@1x.png'));
    expect(contents, contains('"idiom" : "watch-marketing"'));
  });
}
