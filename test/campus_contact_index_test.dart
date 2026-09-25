import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/services/campus_contact_index.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(utf8.encode('{"organizations":[]}')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'public-contact-fixture-',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'startup index persists only public lightweight fields and reopens without fetching again',
    () async {
      var requests = 0;
      var organizationRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/directory/public/organizations') {
          organizationRequests++;
          return http.Response('{"organizations":[]}', 200);
        }
        requests++;
        expect(request.url.path, '/v1/directory/public/contacts');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'name': '示例教师',
                'name_en': 'Example Teacher',
                'email': 'teacher@example.test',
                'unit_names': ['Example School'],
                'photo_url': 'https://staff.bnbu.edu.cn/example.png',
                'document_text': 'This field must not persist',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      CampusContactIndex index() => CampusContactIndex(
        directory: () async => directory,
        bundle: _Bundle(),
        service: RemoteCampusDirectoryService(
          client: client,
          baseUrl: 'https://example.test',
        ),
      );
      final first = index();
      await first.loadLocal();
      expect(requests, 0);
      await first.refresh();
      expect(first.teachers.single.email, 'teacher@example.test');
      final raw = await File(
        '${directory.path}/public-contacts-v1.json',
      ).readAsString();
      expect(raw, isNot(contains('document_text')));
      final reopened = index();
      await reopened.loadLocal();
      expect(reopened.teachers.single.photoUrl, endsWith('example.png'));
      await reopened.refresh();
      expect(requests, 1);
      expect(organizationRequests, 2);
    },
  );

  test(
    'concurrent refreshes coalesce and a corrupt disk index is just a cache miss',
    () async {
      await File(
        '${directory.path}/public-contacts-v1.json',
      ).writeAsString('broken');
      var requests = 0;
      final index = CampusContactIndex(
        directory: () async => directory,
        bundle: _Bundle(),
        service: RemoteCampusDirectoryService(
          baseUrl: 'https://example.test',
          client: MockClient((request) async {
            requests++;
            if (request.url.path.endsWith('/organizations')) {
              return http.Response('{"organizations":[]}', 200);
            }
            return http.Response('{"items":[]}', 200);
          }),
        ),
      );
      await Future.wait([index.refresh(), index.refresh()]);
      expect(requests, 2);
      expect(index.teachers, isEmpty);
    },
  );
}
