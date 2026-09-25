import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:bnbu_me/services/mail_sender_avatar_service.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/teacher_portrait.dart';

class _PortraitCache extends IoMailSenderAvatarService {
  final requests = <String>[];
  final results = <Completer<Uint8List?>>[];
  @override
  Future<Uint8List?> loadTeacherPortrait(
    String url, {
    int dimension = 96,
    bool refresh = false,
  }) {
    requests.add(url);
    final result = Completer<Uint8List?>();
    results.add(result);
    return result.future;
  }
}

void main() {
  final bytes = image.encodePng(image.Image(width: 16, height: 16));
  testWidgets('unavailable portrait retries in place then stops once loaded', (
    tester,
  ) async {
    final cache = _PortraitCache();
    addTearDown(cache.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TeacherPortrait(
          photoUrl: 'https://staff.bnbu.edu.cn/a.jpg',
          size: 144,
          cache: cache,
        ),
      ),
    );
    cache.results.first.complete(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(cache.requests, hasLength(2));
    cache.results.last.complete(bytes);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(cache.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'late portrait from a different teacher cannot replace the current photo',
    (tester) async {
      final cache = _PortraitCache();
      addTearDown(cache.dispose);
      Future<void> mount(String url) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeacherPortrait(photoUrl: url, size: 144, cache: cache),
        ),
      );
      await mount('https://staff.bnbu.edu.cn/a.jpg');
      await mount('https://staff.bnbu.edu.cn/b.jpg');
      cache.results.first.complete(bytes);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      cache.results.last.complete(bytes);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed portrait retry budget is finite and disposed timers stop',
    (tester) async {
      final cache = _PortraitCache();
      addTearDown(cache.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeacherPortrait(
            photoUrl: 'https://staff.bnbu.edu.cn/a.jpg',
            size: 144,
            cache: cache,
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        cache.results.last.complete(null);
        await tester.pump();
        await tester.pump(Duration(seconds: i + 1));
      }
      await tester.pump(const Duration(seconds: 20));
      expect(cache.requests, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
