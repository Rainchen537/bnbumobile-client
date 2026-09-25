import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/widgets/moodle_activity_icon.dart';

void main() {
  test('all supported activity types ship the pinned official SVG', () {
    final provenance =
        jsonDecode(File('assets/moodle/sources.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(provenance['commit'], '090baf556eb30b6baf9dc5fb8f3ac879e186b266');
    final entries = (provenance['assets'] as List).cast<Map<String, dynamic>>();
    expect(
      entries.map((entry) => entry['module']).toSet(),
      moodleActivityAssetTypes,
    );
    for (final type in moodleActivityAssetTypes) {
      final source = File(moodleActivityAssetPath(type)!).readAsStringSync();
      expect(source, contains('<svg'));
      expect(source, isNot(contains('<script')));
      expect(source, isNot(contains('<image')));
    }
  });

  test('normalization keeps unknown modules distinct from assignments', () {
    expect(moodleActivityAssetPath('mod_assign'), 'assets/moodle/assign.svg');
    expect(
      moodleActivityAssetPath('', 'Assignment'),
      'assets/moodle/assign.svg',
    );
    expect(moodleActivityAssetPath('quiz'), 'assets/moodle/quiz.svg');
    expect(moodleActivityAssetPath('feedback'), 'assets/moodle/feedback.svg');
    expect(moodleActivityAssetPath('assignment_planner'), isNull);
    expect(moodleActivityAssetPath('unavailable_plugin'), isNull);
  });

  testWidgets('official artwork keeps the requested size and state color', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MoodleActivityIcon(
              moduleName: 'quiz',
              size: 20,
              color: Colors.red,
              semanticLabel: '测验',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(tester.getSize(find.byType(SvgPicture)), const Size.square(20));
    expect(
      picture.colorFilter,
      const ColorFilter.mode(Colors.red, BlendMode.srcIn),
    );
    expect(find.bySemanticsLabel('测验'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
