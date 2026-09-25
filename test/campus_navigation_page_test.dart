import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_user_place.dart';
import 'package:bnbu_me/pages/campus_navigation_page.dart';
import 'package:bnbu_me/pages/official_campus_map_page.dart';
import 'package:bnbu_me/services/campus_user_place_store.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';

void main() {
  testWidgets(
    'remote landmark opens read-only and does not select an unrelated building',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final landmark = CampusLandmark.fromJson({
        'id': 'test-landmark',
        'category_id': 'buildings',
        'names': {'zh-Hans': '测试地标'},
        'descriptions': {},
        'locations': {},
        'photos': [],
        'position': {
          'longitude': 113.5,
          'latitude': 22.3,
          'coordinate_system': 'GCJ-02',
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CampusNavigationPage(
            initialLandmark: landmark,
            landmarkName: '测试地标',
            mapViewBuilder: _fakeMap,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('测试地标'), findsOneWidget);
      final t1 = find.widgetWithText(ChoiceChip, 'T1 · 师雅楼');
      expect(tester.widget<ChoiceChip>(t1).selected, false);
      await tester.tap(t1);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(t1).selected, true);
      expect(find.text('测试地标'), findsNothing);
    },
  );

  testWidgets('initial query preselects the matching campus place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CampusNavigationPage(
          initialQuery: 'T3-602',
          mapViewBuilder: _fakeMap,
        ),
      ),
    );
    await tester.pump();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.controller?.text, 'T3-602');

    final t3Chip = find.widgetWithText(ChoiceChip, 'T3 · 格物楼');
    expect(t3Chip, findsOneWidget);
    expect(tester.widget<ChoiceChip>(t3Chip).selected, isTrue);
    expect(find.text('Science Building'), findsNothing);
  });

  testWidgets('official map opens inside the app', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: CampusNavigationPage(mapViewBuilder: _fakeMap)),
    );

    await tester.tap(find.byTooltip('打开官方校园地图'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OfficialCampusMapPage), findsOneWidget);
    expect(find.text('官方校园地图'), findsOneWidget);
  });

  testWidgets('amap sdk canvas is embedded directly in campus navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NativeMirrorWebView? capturedWebView;
    await tester.pumpWidget(
      MaterialApp(
        home: CampusNavigationPage(
          initialQuery: 'T3',
          mapViewBuilder: (context, webView) {
            capturedWebView = webView;
            return const ColoredBox(color: Colors.blueGrey);
          },
        ),
      ),
    );
    await tester.pump();

    final webView = capturedWebView!;
    expect(find.text('高德校园地图'), findsOneWidget);
    expect(find.byKey(const ValueKey('campus-open-amap-button')), findsNothing);
    expect(
      webView.content.value,
      'https://api.bnbu.yunwai.cloud/public/campus-map',
    );
    expect(webView.session.useEphemeralSession, isTrue);
    expect(webView.session.cookies, isEmpty);
    expect(
      webView.session.allowedOrigins,
      contains('https://api.bnbu.yunwai.cloud'),
    );
    expect(webView.resourceOnlyDomains, contains('autonavi.com'));
    expect(webView.allowExternalHttpsNavigation, isFalse);
  });

  testWidgets('user can mark and persist a custom campus place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryCampusUserPlaceStore();
    NativeMirrorWebView? capturedWebView;

    await tester.pumpWidget(
      MaterialApp(
        home: CampusNavigationPage(
          owner: 'student@bnbu.edu.cn',
          userPlaceStore: store,
          mapViewBuilder: (context, webView) {
            capturedWebView = webView;
            return const ColoredBox(color: Colors.blueGrey);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('campus-add-place-button')),
    );
    addButton.onPressed!();
    await tester.pump();
    capturedWebView!.onNavigationBlocked!(
      'handsbnbu://campus-map/tap?longitude=113.5428&latitude=22.3635',
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('campus-user-place-name')),
      '排练集合点',
    );
    await tester.enterText(
      find.byKey(const ValueKey('campus-user-place-note')),
      '周四 18:00',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('排练集合点'), findsWidgets);
    expect(find.text('周四 18:00'), findsOneWidget);
    expect(store.savedOwner, 'student@bnbu.edu.cn');
    expect(store.places, hasLength(1));
    expect(store.places.single.longitude, 113.5428);
    expect(store.places.single.latitude, 22.3635);
    expect(store.places.single.mapX, isNull);
  });

  testWidgets('user can edit and delete a saved campus place', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 8, 4, 8);
    final store = _MemoryCampusUserPlaceStore()
      ..places = <CampusUserPlace>[
        CampusUserPlace(
          id: 'saved-place',
          name: '旧名称',
          note: '旧备注',
          mapX: 0.4,
          mapY: 0.6,
          createdAt: now,
          updatedAt: now,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CampusNavigationPage(
          userPlaceStore: store,
          mapViewBuilder: _fakeMap,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '旧名称'));
    await tester.pump();
    await tester.tap(find.byTooltip('编辑地点'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('campus-user-place-name')),
      '新名称',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.places.single.name, '新名称');
    await tester.tap(find.byTooltip('删除地点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(store.places, isEmpty);
    expect(find.text('新名称'), findsNothing);
  });

  testWidgets('campus navigation keeps map actions across breakpoints', (
    tester,
  ) async {
    final store = _MemoryCampusUserPlaceStore();
    for (final size in const <Size>[
      Size(390, 844),
      Size(900, 1200),
      Size(1440, 1000),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: CampusNavigationPage(
            userPlaceStore: store,
            mapViewBuilder: _fakeMap,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('campus-open-amap-button')),
        findsNothing,
      );
      expect(find.text('高德校园地图'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}

Widget _fakeMap(BuildContext context, NativeMirrorWebView webView) {
  return const ColoredBox(color: Colors.blueGrey);
}

class _MemoryCampusUserPlaceStore implements CampusUserPlaceStore {
  List<CampusUserPlace> places = const <CampusUserPlace>[];
  String? savedOwner;

  @override
  Future<List<CampusUserPlace>> load(String owner) async => places;

  @override
  Future<void> save(String owner, List<CampusUserPlace> places) async {
    savedOwner = owner;
    this.places = List<CampusUserPlace>.from(places);
  }
}
