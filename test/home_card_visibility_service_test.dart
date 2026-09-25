import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/home_card_visibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'remote visibility accepts only fixed card keys and caches success',
    () async {
      late http.Request captured;
      final service = RemoteHomeCardVisibilityService(
        baseUrl: 'https://sync.example',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': 7,
              'cards': {
                'duoduo': false,
                'ispace': true,
                'check_in': false,
                'grade_report': false,
                'unknown_remote_component': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final visibility = await service.load();

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/public/home-cards');
      expect(captured.headers, isNot(contains('Authorization')));
      expect(captured.headers, isNot(contains('Cookie')));
      expect(visibility.version, 7);
      expect(visibility.isVisible(HomeServiceCard.duoduo), isFalse);
      expect(visibility.isVisible(HomeServiceCard.ispace), isTrue);
      expect(visibility.isVisible(HomeServiceCard.checkIn), isFalse);
      expect(visibility.isVisible(HomeServiceCard.gradeReport), isFalse);
      expect(visibility.isVisible(HomeServiceCard.portal), isTrue);
      expect(
        visibility.toJson()['cards'],
        isNot(contains('unknown_remote_component')),
      );
      service.dispose();
    },
  );

  test('network failure keeps the last trusted visibility', () async {
    SharedPreferences.setMockInitialValues({
      'home.card_visibility.v1': jsonEncode({
        'schema_version': 1,
        'version': 4,
        'cards': {'duoduo': false},
      }),
    });
    final service = RemoteHomeCardVisibilityService(
      baseUrl: 'https://sync.example',
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    final visibility = await service.load();

    expect(visibility.version, 4);
    expect(visibility.isVisible(HomeServiceCard.duoduo), isFalse);
    expect(visibility.isVisible(HomeServiceCard.portal), isTrue);
    expect(visibility.isVisible(HomeServiceCard.gradeReport), isTrue);
    service.dispose();
  });

  test('first failure safely shows every fixed card', () async {
    final service = RemoteHomeCardVisibilityService(
      baseUrl: 'https://sync.example',
      client: MockClient((_) async => http.Response('{bad json', 200)),
    );

    final visibility = await service.load();

    for (final card in HomeServiceCard.values) {
      expect(visibility.isVisible(card), isTrue);
    }
    service.dispose();
  });

  test('out-of-order responses never downgrade the trusted cache', () async {
    final responses = <Completer<http.Response>>[
      Completer<http.Response>(),
      Completer<http.Response>(),
    ];
    var requestIndex = 0;
    final service = RemoteHomeCardVisibilityService(
      baseUrl: 'https://sync.example',
      client: MockClient((_) => responses[requestIndex++].future),
    );

    final older = service.load();
    final newer = service.load();
    responses[1].complete(
      http.Response(
        jsonEncode({
          'schema_version': 1,
          'version': 8,
          'cards': {'grade_report': false},
        }),
        200,
      ),
    );
    expect((await newer).version, 8);
    responses[0].complete(
      http.Response(
        jsonEncode({
          'schema_version': 1,
          'version': 7,
          'cards': {'grade_report': true},
        }),
        200,
      ),
    );
    expect((await older).version, 8);
    final cached = await service.loadCached();
    expect(cached?.version, 8);
    expect(cached?.isVisible(HomeServiceCard.gradeReport), isFalse);
    service.dispose();
  });
}
