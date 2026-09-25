import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/teacher_review.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const teacherKey = 'tchr_0123456789abcdef0123456789abcdef01234567';

  test('public review query keeps the course-linked filter', () async {
    late Uri requested;
    final service = RemoteTeacherReviewService(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'summary': {
              'count': 1,
              'course_linked_count': 1,
              'overall_rating_counts': [0, 0, 0, 0, 1],
              'overall_average': 4.5,
              'teaching_engagement_average': 5,
              'grading_generosity_average': 4,
              'attendance_frequency_average': 2,
              'feedback_quality_average': 5,
              'course_workload_average': 3,
            },
            'total': 1,
            'offset': 0,
            'limit': 50,
            'items': [_reviewJson()],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      baseUrl: 'https://reviews.example',
    );
    addTearDown(service.dispose);

    final page = await service.loadReviews(teacherKey, courseLinkedOnly: true);

    expect(requested.path, '/v2/directory/public/teachers/$teacherKey/reviews');
    expect(requested.queryParameters['course_linked_only'], 'true');
    expect(requested.queryParameters['offset'], '0');
    expect(requested.queryParameters['limit'], '50');
    expect(page.summary.overallAverage, 4.5);
    expect(page.summary.overallRatingCounts, [0, 0, 0, 0, 1]);
    expect(page.items.single.courseEvidence.single.courseCode, 'COMP1001');
  });

  test('older review summaries remain readable without rating counts', () {
    final summary = TeacherReviewSummary.fromJson(const {
      'count': 1,
      'course_linked_count': 0,
      'overall_average': 4,
    });

    expect(summary.overallRatingCounts, [0, 0, 0, 0, 0]);
  });

  test('saving a review uses the already verified ME device token', () async {
    final store = _MemoryUsageSyncStore();
    await store.saveDevice(
      'v12345678@mail.bnbu.edu.cn',
      const UsageSyncDeviceRecord(
        installationId: 'synthetic-me-installation-0000000000',
        deviceToken: 'dev_teacher-review-token',
      ),
    );
    final requests = <http.Request>[];
    final service = RemoteTeacherReviewService(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/v1/enrollment') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['consent_version'], teacherReviewConsentVersion);
          return http.Response(
            jsonEncode({'device_token': 'dev_teacher-review-token'}),
            201,
          );
        }
        expect(
          request.headers['Authorization'],
          'Bearer dev_teacher-review-token',
        );
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['overall_rating'], 5);
        expect(payload.containsKey('feedback_quality'), isFalse);
        expect(payload['course_evidence'], hasLength(1));
        return http.Response(
          jsonEncode({
            'review': _reviewJson(),
            'suspended_until': null,
            'can_review': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      usageStore: store,
      packageInfoLoader: () async => PackageInfo(
        appName: 'BNBU.ME',
        packageName: 'test',
        version: '1.2.1',
        buildNumber: '2026082401',
      ),
      platformProvider: () => 'ios',
      baseUrl: 'https://reviews.example',
    );
    addTearDown(service.dispose);

    final result = await service.saveReview(
      'v12345678',
      teacherKey,
      const TeacherReviewDraft(
        expectedVersion: 0,
        overallRating: 5,
        teachingEngagement: 5,
        gradingGenerosity: 4,
        attendanceFrequency: 2,
        courseWorkload: 3,
        comment: '讲解清楚',
        courseEvidence: [
          TeacherReviewCourseEvidence(
            courseCode: 'COMP1001',
            courseName: 'Computing Fundamentals',
            semesterId: '2026-S1',
            semesterName: 'Semester 1 of AY2026-27',
          ),
        ],
      ),
    );

    expect(requests, hasLength(1));
    expect(result.review?.version, 1);
    final record = await store.loadDevice('v12345678@mail.bnbu.edu.cn');
    expect(record?.deviceToken, 'dev_teacher-review-token');
  });

  test('a timed moderation restriction is exposed to the editor', () async {
    final store = _MemoryUsageSyncStore();
    await store.saveDevice(
      'v12345678@mail.bnbu.edu.cn',
      const UsageSyncDeviceRecord(
        installationId: '0123456789abcdef0123456789abcdef',
        deviceToken: 'dev_existing',
      ),
    );
    final service = RemoteTeacherReviewService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': {
              'code': 'teacher_review_suspended',
              'suspended_until': '2026-08-27T12:00:00+08:00',
            },
          }),
          403,
        ),
      ),
      usageStore: store,
      baseUrl: 'https://reviews.example',
    );
    addTearDown(service.dispose);

    await expectLater(
      service.saveReview(
        'v12345678',
        teacherKey,
        const TeacherReviewDraft(
          expectedVersion: 0,
          overallRating: 5,
          teachingEngagement: 5,
          gradingGenerosity: 5,
          attendanceFrequency: 5,
          courseWorkload: 5,
          comment: '',
          courseEvidence: [],
        ),
      ),
      throwsA(
        isA<TeacherReviewSuspendedException>().having(
          (error) => error.suspendedUntil?.day,
          'day',
          27,
        ),
      ),
    );
  });
}

Map<String, Object?> _reviewJson() => {
  'id': '00000000-0000-4000-8000-000000000001',
  'teacher_key': 'tchr_0123456789abcdef0123456789abcdef01234567',
  'teacher_name': '陈老师',
  'teacher_name_en': 'Teacher Chen',
  'overall_rating': 5,
  'teaching_engagement': 5,
  'grading_generosity': 4,
  'attendance_frequency': 2,
  'feedback_quality': 5,
  'course_workload': 3,
  'comment': '讲解清楚',
  'course_linked': true,
  'course_evidence': [
    {
      'course_code': 'COMP1001',
      'course_name': 'Computing Fundamentals',
      'semester_id': '2026-S1',
      'semester_name': 'Semester 1 of AY2026-27',
    },
  ],
  'moderation_status': 'visible',
  'hidden_reason': '',
  'version': 1,
  'created_at': '2026-08-24T10:00:00+08:00',
  'updated_at': '2026-08-24T10:00:00+08:00',
};

class _MemoryUsageSyncStore implements UsageSyncStore {
  final Map<String, UsageSyncDeviceRecord> _devices = {};

  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async =>
      _devices[email];

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord record) async =>
      _devices[email] = record;
}
