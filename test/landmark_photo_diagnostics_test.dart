import 'dart:convert';
import 'dart:io';

import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final photo = LandmarkPhoto.fromJson({
    'id': 'a' * 64,
    'focus_x': .5,
    'focus_y': .5,
  });
  Future<File?> diagnostic(Directory dir) async {
    final matches = await dir
        .list(recursive: true)
        .where((f) => f is File && f.path.endsWith('/photo-diagnostics.json'))
        .toList();
    return matches.isEmpty ? null : matches.single as File;
  }

  test('disabled diagnostics retain failure behavior without a log', () async {
    final dir = await Directory.systemTemp.createTemp('photo-diagnostic-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = CampusLandmarkStore(
      directory: () async => dir,
      client: MockClient((_) async => http.Response('secret body', 503)),
    );
    addTearDown(store.dispose);
    expect(await store.photo(photo), isNull);
    expect(await diagnostic(dir), isNull);
  });

  test('bounded HTTP failures exclude response bodies and paths', () async {
    final dir = await Directory.systemTemp.createTemp('photo-diagnostic-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = CampusLandmarkStore(
      directory: () async => dir,
      photoDiagnostics: true,
      client: MockClient((_) async => http.Response('secret body', 503)),
    );
    addTearDown(store.dispose);
    for (var i = 0; i < 42; i++) {
      expect(await store.photo(photo), isNull);
    }
    final body = await (await diagnostic(dir))!.readAsString();
    final events = jsonDecode(body)['events'] as List;
    expect(events, hasLength(40));
    expect(events.last['stage'], 'response_body');
    expect(events.last['http_status'], 503);
    expect(events.last['error'], 'format');
    expect(body, isNot(contains('secret body')));
    expect(body, isNot(contains(dir.path)));
    expect(body, isNot(contains('https://')));
  });

  test('invalid image distinguishes decoding from HTTP failure', () async {
    final dir = await Directory.systemTemp.createTemp('photo-diagnostic-test-');
    addTearDown(() => dir.delete(recursive: true));
    final store = CampusLandmarkStore(
      directory: () async => dir,
      photoDiagnostics: true,
      client: MockClient((_) async => http.Response('invalid image', 200)),
    );
    addTearDown(store.dispose);
    expect(await store.photo(photo), isNull);
    final data = jsonDecode(await (await diagnostic(dir))!.readAsString());
    expect(data['events'].single['stage'], 'image_descriptor');
    expect(data['events'].single['bytes'], 13);
    expect(data['events'].single['http_status'], 200);
  });
}
