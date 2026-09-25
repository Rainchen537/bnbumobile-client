import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/me_life_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'campus_landmarks_test.dart' show fixture;

class RecordingActions extends NativeActions {
  String? opened;
  bool fail = false;
  @override
  Future<void> openExternalUrl(String url) async {
    if (fail) throw StateError('unavailable');
    opened = url;
  }
}

void main() {
  for (final width in [320.0, 402.0, 768.0, 1440.0]) {
    for (final locale in [
      const Locale('zh'),
      const Locale('en'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      testWidgets(
        'published evidence $width $locale stays readable and linked',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final json = fixture();
          json['catalog']['landmarks'][0]['sources'] = [
            {
              'id': 'secret-source-key',
              'title': {
                'zh-Hans': '年度社团资料',
                'zh-Hant': '年度社團資料',
                'en': 'Annual club record',
              },
              'url': 'https://www.bnbu.edu.cn/clubs',
              'publisher': {'zh-Hans': '学生事务处', 'en': 'Student Affairs'},
              'checked_on': '2026-09-16',
              'note': {'zh-Hans': '年度评级', 'en': 'Annual rating'},
            },
          ];
          json['catalog']['landmarks'][0]['facts'] = [
            {
              'id': 'private-fact-key',
              'label': {
                'zh-Hans': '社团星级',
                'zh-Hant': '社團星級',
                'en': 'Club stars',
              },
              'value': {'zh-Hans': '五星', 'en': 'Five stars'},
              'period': '2025–2026',
              'source_ids': ['secret-source-key'],
            },
          ];
          final catalog = LandmarkCatalog.fromJson(json);
          final actions = RecordingActions();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: locale,
              supportedLocales: const [
                Locale('zh'),
                Locale('en'),
                Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
              ],
              localizationsDelegates: const [
                BnbuLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(width == 320 ? 1.8 : 1),
                  ),
                  child: SingleChildScrollView(
                    child: LifeEvidenceDetails(
                      item: catalog.landmarks.first,
                      catalog: catalog,
                      nativeActions: actions,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final english = locale.languageCode == 'en';
          expect(find.textContaining('2025–2026'), findsOneWidget);
          expect(
            find.textContaining(english ? 'Five stars [1]' : '五星 [1]'),
            findsOneWidget,
          );
          expect(find.textContaining('secret-source-key'), findsNothing);
          expect(find.textContaining('private-fact-key'), findsNothing);
          expect(find.byType(ExpansionTile), findsNothing);
          expect(find.byType(TextButton), findsNothing);
          expect(actions.opened, isNull);
          expect(
            catalog.landmarks.first.sources.single.url,
            'https://www.bnbu.edu.cn/clubs',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('legacy entries with no evidence add no section', (tester) async {
    final catalog = LandmarkCatalog.fromJson(fixture());
    await tester.pumpWidget(
      MaterialApp(
        home: LifeEvidenceDetails(
          item: catalog.landmarks.first,
          catalog: catalog,
        ),
      ),
    );
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
  });
}
