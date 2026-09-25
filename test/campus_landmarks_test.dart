import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/services/landmark_review_service.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/pages/campus_landmarks_page.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Map<String, dynamic> fixture({int version = 1}) => {
  'schema_version': 1,
  'version': version,
  'catalog': {
    'default_language': 'zh-Hans',
    'title': {'zh-Hans': '校园地标', 'zh-Hant': '校園地標', 'en': 'Campus Landmarks'},
    'categories': [
      {
        'id': 'buildings',
        'parent_id': null,
        'names': {'zh-Hans': '校园建筑', 'en': 'Buildings'},
      },
      {
        'id': 'food',
        'parent_id': null,
        'names': {'zh-Hans': '美食商超', 'en': 'Food & Shops'},
      },
    ],
    'landmarks': [
      {
        'id': 'lrc',
        'category_id': 'buildings',
        'names': {
          'zh-Hans': '学习资源中心',
          'zh-Hant': '學習資源中心',
          'en': 'Learning Resource Centre',
        },
        'descriptions': {'zh-Hans': '测试介绍', 'en': 'Test description'},
        'locations': {},
        'photos': [],
        'position': null,
      },
      {
        'id': 'coffee',
        'category_id': 'food',
        'names': {'zh-Hans': '测试咖啡店', 'en': 'Test Coffee'},
        'descriptions': {},
        'locations': {},
        'photos': [],
        'position': null,
      },
    ],
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rejects unknown schema, broken references and unverified coordinate systems',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['schema_version'] = 2,
        (j) => j['catalog']['landmarks'][0]['category_id'] = 'missing',
        (j) => j['catalog']['landmarks'][0]['position'] = {
          'longitude': 113,
          'latitude': 23,
          'coordinate_system': 'WGS84',
        },
        (j) => j['catalog']['categories'][0]['parent_id'] = 'buildings',
      ]) {
        final j = fixture();
        mutate(j);
        expect(() => LandmarkCatalog.fromJson(j), throwsFormatException);
      }
    },
  );
  test(
    'cache loads before refresh, survives offline, ignores stale version and supports ETag',
    () async {
      final dir = await Directory.systemTemp.createTemp('landmarks-test-');
      addTearDown(() => dir.delete(recursive: true));
      var status = 200, version = 3;
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/ranking')) return http.Response('', 404);
        requests.add(r);
        return http.Response.bytes(
          utf8.encode(
            status == 200 ? jsonEncode(fixture(version: version)) : '',
          ),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final first = CampusLandmarkStore(
        client: client,
        directory: () async => dir,
        baseUrl: 'https://content.example',
      );
      await first.refresh();
      expect(first.catalog!.version, 3);
      expect(first.failed, false);
      final restored = CampusLandmarkStore(
        client: client,
        directory: () async => dir,
        baseUrl: 'https://content.example',
      );
      await restored.loadLocal();
      expect(restored.catalog!.version, 3);
      status = 503;
      await restored.refresh();
      expect(restored.catalog!.version, 3);
      expect(restored.failed, true);
      status = 200;
      version = 2;
      await restored.refresh();
      expect(restored.catalog!.version, 3);
      status = 304;
      await restored.refresh();
      expect(restored.failed, false);
      expect(requests.last.headers['If-None-Match'], '"landmarks-3"');
      expect(
        requests.every(
          (r) =>
              !r.followRedirects &&
              !r.headers.containsKey('Authorization') &&
              !r.headers.containsKey('Cookie'),
        ),
        true,
      );
      final other = CampusLandmarkStore(
        client: MockClient((_) async => http.Response('', 503)),
        directory: () async => dir,
        baseUrl: 'https://other.example',
      );
      await other.loadLocal();
      expect(other.catalog, isNull);
      other.dispose();
      first.dispose();
      restored.dispose();
    },
  );
  testWidgets('independent cover starts compact gallery on selected image', (
    tester,
  ) async {
    final store = MemoryStore();
    addTearDown(store.dispose);
    final json = fixture();
    final first = {'id': 'a' * 64, 'focus_x': 0.5, 'focus_y': 0.5},
        second = {'id': 'b' * 64, 'focus_x': 0.5, 'focus_y': 0.5};
    json['catalog']['landmarks'][0]['photos'] = [first, second];
    json['catalog']['landmarks'][0]['cover'] = second;
    final landmark = LandmarkCatalog.fromJson(json).landmarks.first;
    expect(landmark.cover!.id, 'b' * 64);
    expect(landmark.photos.first.id, 'a' * 64);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: LandmarkGallery(
              store: store,
              photos: landmark.photos,
              initialPhotoId: landmark.cover!.id,
              title: '图集',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('landmark-gallery-frame')))
          .height,
      lessThanOrEqualTo(260),
    );
    await tester.tap(find.byKey(const ValueKey('landmark-gallery-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      tester
          .widgetList<LandmarkPhotoView>(find.byType(LandmarkPhotoView))
          .every((p) => p.fit == BoxFit.cover),
      isTrue,
    );
    json['catalog']['landmarks'][0]['cover'] = {
      'id': 'c' * 64,
      'focus_x': 0.5,
      'focus_y': 0.5,
    };
    expect(() => LandmarkCatalog.fromJson(json), throwsFormatException);
  });
  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('catalog categories and detail at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.reset);
      final store = MemoryStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CampusLandmarksPage(
            store: store,
            reviewService: EmptyReviews(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('学习资源中心'), findsOneWidget);
      expect(find.text('测试咖啡店'), findsNothing);
      await tester.tap(find.text('美食商超'));
      await tester.pump();
      expect(find.text('测试咖啡店'), findsOneWidget);
      expect(find.text('学习资源中心'), findsNothing);
      await tester.tap(find.text('校园建筑'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('landmark-lrc')));
      await tester.pumpAndSettle();
      expect(find.text('测试介绍'), findsOneWidget);
      expect(find.text('查看位置'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in [
    const Locale('en'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('remote language content $locale', (tester) async {
      final store = MemoryStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          home: CampusLandmarksPage(
            store: store,
            reviewService: EmptyReviews(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale.languageCode == 'en' ? 'Learning Resource Centre' : '學習資源中心',
        ),
        findsOneWidget,
      );
    });
  }
}

class MemoryStore extends CampusLandmarkStore {
  MemoryStore() {
    catalog = LandmarkCatalog.fromJson(fixture());
  }
  @override
  Future<void> refresh() async {}
  @override
  Future<File?> photo(LandmarkPhoto photo, {bool full = false}) async => null;
}

class EmptyReviews extends Fake implements LandmarkReviewService {
  @override
  Future<CommunityPolicy> readPolicy(String id) async =>
      (await browse(id)).policy;
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = "helpful",
    String? rootId,
  }) async => LandmarkReviewPage.fromJson({
    'summary': {'average': null},
    'policy': {
      'level': -1,
      'revision': 0,
      'read_comments': true,
      'read_ratings': true,
      'write_comments': true,
      'write_ratings': true,
      'react': true,
    },
    'total': 0,
    'items': [],
  });
  @override
  Future<LandmarkReviewMine> mine(String username, String id) async =>
      const LandmarkReviewMine();
  @override
  void dispose() {}
}
