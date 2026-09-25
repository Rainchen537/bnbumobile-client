import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/widgets/landmark_reviews_section.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'landmark_reviews_section_test.dart' show Reviews, policy;

class SourceReviews extends Reviews {
  @override
  Future<LandmarkReviewPage> browse(
    String id, {
    int offset = 0,
    String sort = 'helpful',
    String? rootId,
  }) async => LandmarkReviewPage.fromJson({
    'policy': policy,
    'summary': {
      'average': 8.0,
      'count': 4,
      'counts': [0, 0, 0, 4, 0],
    },
    'rating_summary': {
      'scale': 10,
      'score': 8.6,
      'basis': 'blended',
      'internal': {'score': 8.0, 'count': 4},
      'external': {'score': 9.0, 'count': 50},
    },
    'total': 2,
    'items': [
      {
        'id': 'native',
        'body': '周末在这里吃了午饭，份量很足。下课过来走几分钟就能到。',
        'author': {'name': '校园同学', 'seed': 'native'},
        'stars': 4,
        'version': 1,
        'helpful': 12,
        'created_at': '2026-09-16T00:00:00Z',
        'updated_at': '2026-09-16T00:00:00Z',
        'reply_preview': {
          'id': 'reply',
          'body': '我也喜欢这里的午餐。',
          'author': {'name': '另一位同学', 'seed': 'reply'},
          'stars': 5,
          'version': 1,
          'created_at': '2026-09-16T00:00:00Z',
          'updated_at': '2026-09-16T00:00:00Z',
        },
      },
      {
        'id': 'external:test:1',
        'source': '25doer',
        'read_only': true,
        'body': '餐品味道不错，包装也很整齐。',
        'rating_score': 9.0,
        'merchant_reply': '谢谢支持。',
        'author': {'name': '25度用户', 'seed': 'source'},
        'version': 1,
        'created_at': '2026-09-15T00:00:00Z',
        'updated_at': '2026-09-15T00:00:00Z',
      },
    ],
  });
}

void main() {
  if (Platform.environment['SOURCE_REVIEW_RENDER'] == '1') {
    setUpAll(() async {
      for (final family in ['Roboto', 'Preview']) {
        await (FontLoader(family)..addFont(
              File(
                '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
              ).readAsBytes().then((v) => ByteData.sublistView(v)),
            ))
            .load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
            rootBundle.load(
              'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
            ),
          ))
          .load();
    });
  }
  for (final config in [
    (402.0, 1.0, false),
    (320.0, 1.7, true),
    (900.0, 1.0, true),
  ]) {
    testWidgets('source rows have no native actions at $config', (
      tester,
    ) async {
      tester.view.physicalSize = Size(config.$1, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final service = SourceReviews();
      await tester.pumpWidget(
        MaterialApp(
          theme: (config.$3 ? AppTheme.dark : AppTheme.light).copyWith(
            textTheme: (config.$3 ? AppTheme.dark : AppTheme.light).textTheme
                .apply(fontFamily: 'Preview'),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(config.$1, 1400),
              textScaler: TextScaler.linear(config.$2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: config.$3 ? const Color(0xff14171b) : Colors.white,
                  child: SingleChildScrollView(
                    child: LandmarkReviewsSection(
                      landmarkId: 'fixture',
                      username: 'fixture',
                      service: service,
                      toolbar: ValueNotifier<Widget?>(null),
                      onShare: (_, _) async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('8.6'), findsOneWidget);
      final source = find.byKey(const ValueKey('review-row-external:test:1'));
      expect(source, findsOneWidget);
      for (final label in ['回复', '编辑', '分享']) {
        expect(
          find.descendant(of: source, matching: find.byTooltip(label)),
          findsNothing,
        );
      }
      expect(
        find.descendant(of: source, matching: find.byIcon(Icons.thumb_up)),
        findsNothing,
      );
      expect(find.text('25度评价'), findsOneWidget);
      expect(find.text('商家回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['SOURCE_REVIEW_RENDER'] == '1' &&
          config.$1 == 402) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/source-sync/reviews-reference.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }
}
