import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/moodle_runtime_profile.dart';
import 'package:bnbu_me/services/moodle_api_client.dart';

void main() {
  test(
    'identity reads reject third-party avatar sources and never transmit school token',
    () async {
      final requests = <http.Request>[];
      final client = MoodleApiClient(
        baseUrl: 'https://ispace.example',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              'fullname': 'Test Student',
              'userpictureurl': 'https://external.example/photo.png',
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await client.fetchIdentity(token: 'fixture-token');
      expect(result.name, 'Test Student');
      expect(result.avatar, isNull);
      expect(requests.length, 1);
      expect(requests.single.url.host, 'ispace.example');
    },
  );
  test('disabled picture capability performs zero requests', () async {
    var requests = 0;
    final client = MoodleApiClient(
      baseUrl: 'https://ispace.example',
      client: MockClient((r) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.updateOwnPicture(
        token: 'fixture-token',
        jpeg: Uint8List.fromList([1, 2]),
      ),
      throwsA(isA<MoodleFeatureUnavailableException>()),
    );
    expect(requests, 0);
  });
  for (final success in [true, 1, false, 0]) {
    test(
      'official picture update accepts Moodle PARAM_BOOL $success',
      () async {
        final functions = <String>[];
        final client = MoodleApiClient(
          baseUrl: 'https://ispace.example',
          client: MockClient((r) async {
            if (r.url.path.endsWith('upload.php')) {
              return http.Response(
                jsonEncode([
                  {'itemid': 42, 'filename': 'avatar.jpg'},
                ]),
                200,
              );
            }
            final f = r.bodyFields['wsfunction']!;
            functions.add(f);
            if (f == 'core_files_get_unused_draft_itemid') {
              return http.Response('{"itemid":42}', 200);
            }
            expect(f, 'core_user_update_picture');
            expect(r.bodyFields['userid'], '0');
            expect(r.bodyFields['delete'], '0');
            expect(r.bodyFields['draftitemid'], '42');
            return http.Response(
              jsonEncode({'success': success, 'warnings': []}),
              200,
            );
          }),
        );
        addTearDown(client.dispose);
        client.cacheRuntimeProfileForTesting(
          token: 'fixture-token',
          profile: MoodleRuntimeProfile.fromSiteInfo({
            'uploadfiles': 1,
            'functions': [
              {'name': 'core_files_get_unused_draft_itemid'},
              {'name': 'core_user_update_picture'},
            ],
          }),
        );
        final update = client.updateOwnPicture(
          token: 'fixture-token',
          jpeg: Uint8List.fromList([1, 2, 3]),
        );
        if (success == true || success == 1) {
          await update;
        } else {
          await expectLater(update, throwsA(isA<MoodleApiException>()));
        }
        expect(functions, [
          'core_files_get_unused_draft_itemid',
          'core_user_update_picture',
        ]);
      },
    );
  }
}
