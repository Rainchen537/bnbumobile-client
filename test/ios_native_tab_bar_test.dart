import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_liquid_glass.dart';
import 'package:bnbu_me/widgets/campus_primary_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('compact navigation uses the registered native system tab bridge', () {
    final rootShell = File('lib/pages/root_shell_page.dart').readAsStringSync();
    final navigation = File(
      'lib/widgets/campus_primary_navigation.dart',
    ).readAsStringSync();
    final liquidGlass = File(
      'lib/widgets/bnbu_liquid_glass.dart',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(navigation, contains('BnbuNativeLiquidGlassTabBar('));
    expect(
      rootShell,
      contains('CampusPrimaryNavigation.usesLiquidGlass(context)'),
    );
    expect(rootShell, isNot(contains('root-liquid-glass-selected-pill')));
    expect(liquidGlass, contains("viewType: 'ispace/native_tab_bar'"));
    expect(
      liquidGlass,
      contains("MethodChannel('ispace/native_tab_bar/\$viewId')"),
    );
    expect(liquidGlass, contains("invokeMethod<void>('setLabels'"));

    expect(appDelegate, contains('withId: "ispace/native_tab_bar"'));
    expect(appDelegate, contains('private let tabBar: UITabBar'));
    expect(appDelegate, contains('tabBar.delegate = self'));
    expect(appDelegate, contains('func tabBar(_ tabBar: UITabBar, didSelect'));
    expect(
      appDelegate,
      contains('channel.invokeMethod("selectedIndexChanged"'),
    );
    expect(appDelegate, contains('case "setLabels":'));
    expect(appDelegate, contains('item.title = label'));
    expect(
      appDelegate,
      contains(
        'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
      ),
    );
    expect(
      appDelegate,
      contains(
        'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w400.ttf',
      ),
    );
    expect(appDelegate, isNot(contains('selectionIndicatorImage')));
  });

  testWidgets(
    'native tabs preserve order, taps, programmatic selection and locale',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final appearance = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      addTearDown(appearance.dispose);
      await appearance.restore();
      final messenger = tester.binding.defaultBinaryMessenger;
      final updates = <MethodCall>[];
      String? channelName;
      Map<Object?, Object?>? parameters;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final arguments = call.arguments as Map;
          expect(arguments['viewType'], 'ispace/native_tab_bar');
          parameters =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(arguments['params'] as Uint8List),
                  )
                  as Map<Object?, Object?>;
          channelName = 'ispace/native_tab_bar/${arguments['id']}';
          final channel = MethodChannel(channelName!);
          messenger.setMockMethodCallHandler(channel, (call) async {
            updates.add(call);
            return null;
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );

      var selected = AppTab.schedule;
      var locale = const Locale('zh', 'CN');
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
              locale: locale,
              supportedLocales: BnbuLocalizations.supportedLocales,
              localizationsDelegates: const [
                BnbuLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: MediaQuery(
                data: const MediaQueryData(
                  viewPadding: EdgeInsets.only(bottom: 34),
                ),
                child: BnbuLiquidGlassScope(
                  controller: appearance,
                  child: Scaffold(
                    bottomNavigationBar: CampusPrimaryNavigation(
                      wide: false,
                      selectedTab: selected,
                      onSelected: (tab) => setState(() => selected = tab),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(parameters!['labels'], ['首页', '邮箱', 'iSpace', '课表', '我的']);
      expect(parameters!['selectedIndex'], 3);
      expect(parameters!['iconCodePoints'], hasLength(5));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('root-bottom-navigation')))
            .height,
        98,
      );

      for (var index = 0; index < campusNavigationTabs.length; index++) {
        await messenger.handlePlatformMessage(
          channelName!,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('selectedIndexChanged', index),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(selected, campusNavigationTabs[index]);
      }
      for (final invalid in [-1, 5, '1']) {
        await messenger.handlePlatformMessage(
          channelName!,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('selectedIndexChanged', invalid),
          ),
          (_) {},
        );
      }
      expect(selected, AppTab.user);
      updates.clear();
      rebuild(() {
        selected = AppTab.ispace;
        locale = const Locale('en');
      });
      await tester.pumpAndSettle();
      expect(
        updates.any(
          (call) => call.method == 'setSelectedIndex' && call.arguments == 2,
        ),
        isTrue,
      );
      expect(
        updates.lastWhere((call) => call.method == 'setLabels').arguments,
        ['Home', 'Mail', 'iSpace', 'Timetable', 'Me'],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final scenario in [
    (
      name: 'unsupported iOS',
      platform: TargetPlatform.iOS,
      supported: false,
      wide: false,
      contrast: false,
    ),
    (
      name: 'Android',
      platform: TargetPlatform.android,
      supported: true,
      wide: false,
      contrast: false,
    ),
    (
      name: 'high contrast',
      platform: TargetPlatform.iOS,
      supported: true,
      wide: false,
      contrast: true,
    ),
    (
      name: 'wide sidebar',
      platform: TargetPlatform.iOS,
      supported: true,
      wide: true,
      contrast: false,
    ),
  ]) {
    testWidgets('${scenario.name} retains non-glass navigation', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final appearance = AppThemeModeController(
        liquidGlassSupportLoader: () async => scenario.supported,
      );
      addTearDown(appearance.dispose);
      await appearance.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: scenario.platform),
          home: MediaQuery(
            data: MediaQueryData(highContrast: scenario.contrast),
            child: BnbuLiquidGlassScope(
              controller: appearance,
              child: Scaffold(
                body: CampusPrimaryNavigation(
                  wide: scenario.wide,
                  selectedTab: AppTab.home,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BnbuNativeLiquidGlassTabBar), findsNothing);
      expect(
        find.byKey(const ValueKey('root-ios-liquid-glass-navigation')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey(
            scenario.wide ? 'root-side-navigation' : 'root-bottom-navigation',
          ),
        ),
        findsOneWidget,
      );
    });
  }
}
