import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/landmark_review.dart';
import 'package:bnbu_me/services/landmark_review_service.dart';
import 'package:bnbu_me/services/teacher_review_service.dart';

class Identity extends Fake implements RemoteTeacherReviewService {
  int enrolled = 0, invalidated = 0;
  String? consent;
  @override
  Future<String?> existingReviewDeviceToken(String username) async =>
      'test-device';
  @override
  Future<String> ensureReviewDeviceToken(
    String username, {
    required String consentVersion,
  }) async {
    enrolled++;
    consent = consentVersion;
    return 'test-device';
  }

  @override
  Future<void> invalidateReviewDeviceToken(String username) async {
    invalidated++;
  }
}

const policy = {
  'level': -1,
  'revision': 0,
  'read_comments': true,
  'read_ratings': true,
  'write_comments': true,
  'write_ratings': true,
  'react': true,
};

void main() {
  test(
    'public reads are anonymous; saves use integer score and independent consent with bounded 401 retry',
    () async {
      final identity = Identity();
      final requests = <http.Request>[];
      var writes = 0;
      final service = RemoteLandmarkReviewService(
        identity: identity,
        baseUrl: 'https://reviews.example',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PUT' && writes++ == 0) {
            return http.Response('', 401);
          }
          return http.Response(
            jsonEncode(
              request.method == 'GET'
                  ? {
                      'items': [],
                      'total': 10,
                      'summary': {'average': 9.8},
                      'policy': policy,
                    }
                  : {'comment': null, 'can_review': true, 'policy': policy},
            ),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      expect((await service.browse('lrc')).average, 9.8);
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
      expect(identity.enrolled, 0);
      await service.rate('student', 'lrc', version: 0, stars: 4);
      expect(identity.enrolled, 2);
      expect(identity.invalidated, 1);
      expect(identity.consent, landmarkReviewConsentVersion);
      final payload = jsonDecode(requests.last.body) as Map;
      expect(payload['stars'], isA<int>());
      expect(payload['stars'], 4);
      expect(payload['consent_version'], landmarkReviewConsentVersion);
      expect(
        requests.every(
          (r) => !r.followRedirects && !r.headers.containsKey('Cookie'),
        ),
        isTrue,
      );
    },
  );

  test(
    'conflicts do not replay writes and invalid scores never send requests',
    () async {
      var writes = 0;
      final service = RemoteLandmarkReviewService(
        identity: Identity(),
        baseUrl: 'https://reviews.example',
        client: MockClient((r) async {
          writes++;
          return http.Response('', 409);
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.rate('student', 'lrc', version: 1, stars: 5),
        throwsA(
          isA<LandmarkReviewHttpException>().having(
            (e) => e.status,
            'status',
            409,
          ),
        ),
      );
      expect(writes, 1);
      await expectLater(
        service.rate('student', 'lrc', version: 1, stars: 6),
        throwsFormatException,
      );
      expect(writes, 1);
    },
  );
}
