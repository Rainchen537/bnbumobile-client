import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/services/teacher_review_reference_repository.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.references);
  final List<Map<String, dynamic>> references;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(jsonEncode({'schema_version': 1, 'references': references})),
    ),
  );
}

Map<String, dynamic> entry(String id, String scope) => {
  'id': id,
  'scope': scope,
  'teacher_keys': scope == 'teacher' ? ['synthetic-teacher'] : <String>[],
  'course_codes': ['DEMO1001'],
  'course_names': ['Synthetic Course'],
  'source_label': 'Synthetic fixture',
  'source_url': 'https://example.org/reference',
  'summary': 'A fictional reference used only by tests.',
  'highlights': <String>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public asset contains no historical personal reviews', () async {
    final repository = AssetTeacherReviewReferenceRepository();
    expect(
      await repository.loadFor(
        teacherKey: 'synthetic-teacher',
        courseEvidence: const [],
      ),
      isEmpty,
    );
  });

  test('teacher references require their exact synthetic identity', () async {
    final repository = AssetTeacherReviewReferenceRepository(
      assetBundle: _Bundle([entry('teacher', 'teacher')]),
    );
    expect(
      await repository.loadFor(
        teacherKey: 'synthetic-teacher',
        courseEvidence: const [],
      ),
      hasLength(1),
    );
    expect(
      await repository.loadFor(teacherKey: 'other', courseEvidence: const []),
      isEmpty,
    );
  });

  test('course references require matching code or name evidence', () async {
    final repository = AssetTeacherReviewReferenceRepository(
      assetBundle: _Bundle([entry('course', 'course')]),
    );
    expect(
      await repository.loadFor(teacherKey: 'other', courseEvidence: const []),
      isEmpty,
    );
    for (final code in ['DEMO1001', '']) {
      final matches = await repository.loadFor(
        teacherKey: 'other',
        courseEvidence: [
          TeacherReviewCourseEvidence(
            courseCode: code,
            courseName: 'Synthetic Course',
            semesterId: 'demo',
            semesterName: 'Synthetic semester',
          ),
        ],
      );
      expect(matches, hasLength(1));
      expect(matches.single.teacherKeys, isEmpty);
    }
  });

  test('duplicate references fail closed', () async {
    final repository = AssetTeacherReviewReferenceRepository(
      assetBundle: _Bundle([entry('same', 'course'), entry('same', 'course')]),
    );
    await expectLater(
      repository.loadFor(teacherKey: 'other', courseEvidence: const []),
      throwsFormatException,
    );
  });
}
