import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/teacher_review.dart';
import '../models/teacher_review_reference.dart';

abstract interface class TeacherReviewReferenceRepository {
  Future<List<TeacherReviewReference>> loadFor({
    required String teacherKey,
    required Iterable<TeacherReviewCourseEvidence> courseEvidence,
  });
}

class AssetTeacherReviewReferenceRepository
    implements TeacherReviewReferenceRepository {
  AssetTeacherReviewReferenceRepository({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  static const assetPath = 'assets/catalog/teacher_review_references.json';

  final AssetBundle _assetBundle;
  Future<List<TeacherReviewReference>>? _referencesFuture;

  @override
  Future<List<TeacherReviewReference>> loadFor({
    required String teacherKey,
    required Iterable<TeacherReviewCourseEvidence> courseEvidence,
  }) async {
    final references = await (_referencesFuture ??= _loadAll());
    final evidence = courseEvidence.toList(growable: false);
    return references
        .where(
          (reference) =>
              reference.matchesTeacher(teacherKey) ||
              (reference.scope == TeacherReviewReferenceScope.course &&
                  reference.matchesCourseEvidence(evidence)),
        )
        .toList(growable: false);
  }

  Future<List<TeacherReviewReference>> _loadAll() async {
    final decoded = jsonDecode(await _assetBundle.loadString(assetPath));
    if (decoded is! Map<String, dynamic> || decoded['schema_version'] != 1) {
      throw const FormatException('选课参考数据版本无效。');
    }
    final rawReferences = decoded['references'];
    if (rawReferences is! List) {
      throw const FormatException('选课参考数据缺少条目。');
    }
    final references = rawReferences
        .whereType<Map>()
        .map(
          (item) =>
              TeacherReviewReference.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
    final ids = references.map((item) => item.id).toSet();
    if (ids.length != references.length) {
      throw const FormatException('选课参考数据包含重复条目。');
    }
    return List<TeacherReviewReference>.unmodifiable(references);
  }
}
