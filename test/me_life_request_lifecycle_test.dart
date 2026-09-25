import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/home_navigation_stack.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'me_life_catalog_test.dart' show CatalogFixture, openPolicy;

http.Response selection() => http.Response(
  jsonEncode({'policy': openPolicy, 'score': 8.4, 'rating_count': 2}),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed presentation can retry the same key without a catalog refresh',
    () async {
      var calls = 0;
      final store = CampusLandmarkStore(
        client: MockClient((_) async {
          return ++calls == 1 ? http.Response('', 503) : selection();
        }),
      );
      addTearDown(store.dispose);
      await expectLater(store.presentation('unit', 0), throwsFormatException);
      expect((await store.presentation('unit', 0)).score, 8.4);
      await store.presentation('unit', 0);
      expect(calls, 2);
    },
  );

  test(
    'simultaneous policy consumers share only the in-flight request',
    () async {
      var calls = 0;
      final reply = Completer<http.Response>();
      final store = CampusLandmarkStore(
        client: MockClient((_) {
          calls++;
          return reply.future;
        }),
      );
      addTearDown(store.dispose);
      final first = store.presentationPolicy('unit');
      final second = store.presentationPolicy('unit');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      reply.complete(http.Response(jsonEncode(openPolicy), 200));
      expect((await first).readRatings, isTrue);
      await second;
      await store.presentationPolicy('unit');
      expect(calls, 2);
    },
  );

  test(
    'policy revocation prevents a late selection from repopulating cache',
    () async {
      final slow = Completer<http.Response>();
      var reads = 0;
      final store = CampusLandmarkStore(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/policy')) {
            return http.Response(jsonEncode({'level': 3, 'revision': 2}), 200);
          }
          return ++reads == 1 ? slow.future : selection();
        }),
      );
      addTearDown(store.dispose);
      final old = store.presentation('unit', 0);
      await store.presentationPolicy('unit');
      slow.complete(selection());
      await old;
      await store.presentation('unit', 0);
      expect(reads, 2);
    },
  );

  test(
    'public reads have a bounded queue and coalesce duplicate selections',
    () async {
      final barrier = Completer<void>();
      var active = 0, peak = 0, calls = 0;
      final store = CampusLandmarkStore(
        client: MockClient((_) async {
          calls++;
          active++;
          if (active > peak) peak = active;
          await barrier.future;
          active--;
          return selection();
        }),
      );
      addTearDown(store.dispose);
      final jobs = [
        for (var i = 0; i < 12; i++) store.presentation('unit-$i', 0),
      ];
      jobs.add(store.presentation('unit-0', 0));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 4);
      barrier.complete();
      await Future.wait(jobs);
      expect(peak, 4);
      expect(calls, 12);
    },
  );

  test('cached image is not blocked by a slow image download', () async {
    final root = await Directory.systemTemp.createTemp('me-life-queue-');
    addTearDown(() => root.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFF005BAC), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    final slow = Completer<http.Response>();
    final started = Completer<void>();
    var calls = 0;
    final store = CampusLandmarkStore(
      directory: () async => root,
      client: MockClient((request) {
        calls++;
        if (request.url.path.contains('b' * 64)) {
          started.complete();
          return slow.future;
        }
        return Future.value(http.Response.bytes(bytes, 200));
      }),
    );
    addTearDown(store.dispose);
    final cached = LandmarkPhoto.fromJson({
      'id': 'a' * 64,
      'focus_x': .5,
      'focus_y': .5,
    });
    expect(await store.photo(cached), isNotNull);
    final pending = store.photo(
      LandmarkPhoto.fromJson({'id': 'b' * 64, 'focus_x': .5, 'focus_y': .5}),
    );
    await started.future;
    try {
      expect(
        await store.photo(cached).timeout(const Duration(seconds: 2)),
        isNotNull,
      );
      expect(calls, 2);
    } finally {
      slow.complete(http.Response('', 503));
      await pending;
    }
  });

  testWidgets(
    'inactive navigation tab pauses policies and rechecks on return',
    (tester) async {
      final store = CatalogFixture();
      addTearDown(store.dispose);
      Widget scene(bool active) => MaterialApp(
        theme: AppTheme.light,
        home: NavigationTabScope(
          active: active,
          child: Scaffold(
            body: LifeUnitRow(
              item: store.catalog!.landmarks.first,
              catalog: store.catalog!,
              store: store,
              epoch: 0,
              scale: 1,
              onOpen: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(true));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 21));
      expect(store.policyReads, 1);
      await tester.pumpWidget(scene(false));
      await tester.pump(const Duration(seconds: 41));
      expect(store.policyReads, 1);
      await tester.pumpWidget(scene(true));
      await tester.pumpAndSettle();
      expect(store.policyReads, 2);
      expect(store.reads, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('covered route pauses list policies while detail is visible', (
    tester,
  ) async {
    final store = CatalogFixture();
    addTearDown(store.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: AppTheme.light,
        home: Scaffold(
          body: LifeUnitRow(
            item: store.catalog!.landmarks.first,
            catalog: store.catalog!,
            store: store,
            epoch: 0,
            scale: 1,
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    final reads = store.policyReads;
    await tester.pump(const Duration(seconds: 41));
    expect(store.policyReads, reads);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(store.policyReads, reads + 1);
    await tester.pumpWidget(const SizedBox());
  });
}
