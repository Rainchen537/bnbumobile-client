import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/services/app_about_service.dart';

Map<String, dynamic> snapshot(
  int version, {
  List<Object> contacts = const [],
}) => {'schema_version': 1, 'version': version, 'contacts': contacts};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'public config caches per source and preserves last valid content on errors',
    () async {
      var requests = 0;
      var fail = false;
      final service = AppAboutService(
        baseUrl: 'https://app.example',
        client: MockClient((r) async {
          requests++;
          expect(
            r.headers.keys.any(
              (key) => ['authorization', 'cookie'].contains(key.toLowerCase()),
            ),
            isFalse,
          );
          expect(r.followRedirects, isFalse);
          return fail
              ? http.Response('invalid', 500)
              : http.Response(
                  jsonEncode(
                    snapshot(
                      2,
                      contacts: [
                        {
                          'label': 'Support',
                          'kind': 'email',
                          'value': 'support@example.com',
                        },
                      ],
                    ),
                  ),
                  200,
                );
        }),
      );
      final empty = await service.loadCached();
      expect(empty.contacts, isEmpty);
      expect(requests, 0);
      final loaded = await service.refresh(empty);
      expect(
        loaded.contacts.single.target.toString(),
        'mailto:support@example.com',
      );
      expect((await service.loadCached()).version, 2);
      fail = true;
      expect((await service.refresh(loaded)).contacts.single.label, 'Support');
      final other = AppAboutService(baseUrl: 'https://other.example');
      expect((await other.loadCached()).contacts, isEmpty);
      other.dispose();
      service.dispose();
    },
  );
  test('reject malformed contacts and unsupported schemes', () {
    for (final item in [
      {'label': 'X', 'kind': 'website', 'value': 'javascript:alert(1)'},
      {
        'label': 'X',
        'kind': 'website',
        'value': 'https://user:pass@example.com',
      },
      {'label': 'X', 'kind': 'website', 'value': 'https://example.com:8080'},
      {'label': 'X', 'kind': 'email', 'value': 'x@example.com?subject=hello'},
      {'label': 'X', 'kind': 'text', 'value': 'a\nb'},
    ]) {
      expect(() => DeveloperContact.fromJson(item), throwsFormatException);
    }
    expect(
      () => AppAboutConfiguration.fromJson(
        snapshot(1, contacts: List.filled(13, {})),
      ),
      throwsFormatException,
    );
  });
  test('oversized and older responses do not replace cached config', () async {
    for (final body in [' ' * 33000, jsonEncode(snapshot(1))]) {
      final service = AppAboutService(
        baseUrl: 'https://app.example',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      expect(
        (await service.refresh(
          const AppAboutConfiguration(version: 4),
        )).version,
        4,
      );
      service.dispose();
    }
  });
}
