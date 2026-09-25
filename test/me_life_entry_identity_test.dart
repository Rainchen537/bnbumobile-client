import 'dart:async';

import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/models/me_life_presentation.dart';
import 'package:bnbu_me/pages/campus_landmarks_page.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/me_life_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'campus_landmarks_test.dart' show MemoryStore;

LifeUnitPresentation presentation(String? text) =>
    LifeUnitPresentation.fromJson({
      'policy': {
        'read_comments': true,
        'read_ratings': true,
        'level': -1,
        'revision': 1,
      },
      'score': text == null ? null : 9.0,
      'content': text == null
          ? null
          : {'kind': 'review', 'text': text, 'style_id': ''},
    });

class PendingStore extends MemoryStore {
  final responses = <String, Completer<LifeUnitPresentation>>{};
  @override
  Future<void> loadLocal() async {}
  @override
  Future<LifeUnitPresentation> presentation(String id, int cursor) =>
      responses.putIfAbsent(id, Completer.new).future;
  @override
  Future<CommunityPolicy> presentationPolicy(String id) async =>
      CommunityPolicy.fromJson({
        'read_comments': true,
        'read_ratings': true,
        'level': -1,
        'revision': 1,
      });
}

class PendingPolicyStore extends PendingStore {
  final policies = <Completer<CommunityPolicy>>[];
  @override
  Future<CommunityPolicy> presentationPolicy(String id) {
    final request = Completer<CommunityPolicy>();
    policies.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('old policy completion cannot clear the current policy request', (
    tester,
  ) async {
    final store = PendingPolicyStore();
    addTearDown(store.dispose);
    Widget row(int index) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LifeUnitRow(
          item: store.catalog!.landmarks[index],
          catalog: store.catalog!,
          store: store,
          epoch: 0,
          scale: 1,
          onOpen: () {},
        ),
      ),
    );
    await tester.pumpWidget(row(0));
    store.responses['lrc']!.complete(presentation('Old entry'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 21));
    expect(store.policies.length, 1);
    await tester.pumpWidget(row(1));
    await tester.pump(const Duration(seconds: 21));
    expect(store.policies.length, 2);
    store.policies[0].complete(
      CommunityPolicy.fromJson({'level': 3, 'revision': 99}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(store.policies.length, 2);
    store.policies[1].complete(
      CommunityPolicy.fromJson({
        'read_comments': true,
        'read_ratings': false,
        'level': -1,
        'revision': 2,
      }),
    );
    await tester.pump();
    store.responses['coffee']!.complete(presentation('New entry'));
    await tester.pumpAndSettle();
    expect(find.text('New entry'), findsOneWidget);
    expect(find.text('Old entry'), findsNothing);
    expect(find.text('9.0分'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late old entry response cannot replace the current entry', (
    tester,
  ) async {
    final store = PendingStore();
    addTearDown(store.dispose);
    Widget row(int index) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LifeUnitRow(
          item: store.catalog!.landmarks[index],
          catalog: store.catalog!,
          store: store,
          epoch: 0,
          scale: 1,
          onOpen: () {},
        ),
      ),
    );
    await tester.pumpWidget(row(0));
    await tester.pumpWidget(row(1));
    store.responses['coffee']!.complete(presentation('Current entry'));
    await tester.pumpAndSettle();
    store.responses['lrc']!.complete(presentation('Late old entry'));
    await tester.pumpAndSettle();
    expect(find.text('Current entry'), findsOneWidget);
    expect(find.text('Late old entry'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('replacement failure cannot restore the previous entry comment', (
    tester,
  ) async {
    final store = PendingStore();
    addTearDown(store.dispose);
    Widget row(int index) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: LifeUnitRow(
          item: store.catalog!.landmarks[index],
          catalog: store.catalog!,
          store: store,
          epoch: 0,
          scale: 1,
          onOpen: () {},
        ),
      ),
    );
    await tester.pumpWidget(row(0));
    store.responses['lrc']!.complete(presentation('Previous comment'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(row(1));
    expect(find.text('Previous comment'), findsNothing);
    store.responses['coffee']!.completeError(StateError('temporary failure'));
    await tester.pumpAndSettle();
    expect(find.text('Previous comment'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [900.0, 1440.0]) {
    testWidgets(
      'desktop category switch isolates pending entry presentation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = PendingStore();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: CampusLandmarksPage(store: store),
          ),
        );
        await tester.pumpAndSettle();
        store.responses['lrc']!.complete(
          presentation('Only the old building comment'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Only the old building comment'), findsOneWidget);
        await tester.tap(find.text('美食商超'));
        await tester.pump();
        expect(find.text('测试咖啡店'), findsOneWidget);
        expect(find.text('Only the old building comment'), findsNothing);
        expect(find.text('9.0分'), findsNothing);
        store.responses['coffee']!.complete(presentation(null));
        await tester.pumpAndSettle();
        expect(find.text('Only the old building comment'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final replaceStore in [false, true]) {
    testWidgets(
      'unkeyed row clears old identity before asynchronous replacement: store=$replaceStore',
      (tester) async {
        final first = PendingStore(), second = PendingStore();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        Widget row(PendingStore store, int index) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LifeUnitRow(
              item: store.catalog!.landmarks[index],
              catalog: store.catalog!,
              store: store,
              epoch: 0,
              scale: 1,
              onOpen: () {},
            ),
          ),
        );
        await tester.pumpWidget(row(first, 0));
        first.responses['lrc']!.complete(presentation('Old identity'));
        await tester.pumpAndSettle();
        expect(find.text('Old identity'), findsOneWidget);
        final next = replaceStore ? second : first;
        await tester.pumpWidget(row(next, replaceStore ? 0 : 1));
        expect(find.text('Old identity'), findsNothing);
        next.responses[replaceStore ? 'lrc' : 'coffee']!.complete(
          presentation('Correct identity'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Correct identity'), findsOneWidget);
        expect(find.text('Old identity'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
