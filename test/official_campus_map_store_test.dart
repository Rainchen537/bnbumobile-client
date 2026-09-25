import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:bnbu_me/services/official_campus_map_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Uint8List artwork;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('campus-map-test-');
    artwork = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 2, height: 2)),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'public offline first launch has no unlicensed bundled artwork',
    () async {
      var calls = 0;
      final store = OfficialCampusMapStore(
        directory: () async => directory,
        client: MockClient((_) async {
          calls++;
          throw const SocketException('offline');
        }),
      );
      addTearDown(store.dispose);
      await store.loadLocal();
      expect(store.bytes, isNull);
      await expectLater(store.localPath(), throwsA(anything));
      expect(calls, 0);
      await store.refresh();
      expect(store.bytes, isNull);
      await expectLater(store.localPath(), throwsA(anything));
      expect(calls, 1);
    },
  );

  test(
    'validated cache survives restart and bad updates; refresh is bounded',
    () async {
      var calls = 0;
      var response = http.Response.bytes(artwork, 200);
      final store = OfficialCampusMapStore(
        directory: () async => directory,
        client: MockClient((request) async {
          calls++;
          expect(request.url.toString(), OfficialCampusMapStore.imageUrl);
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return response;
        }),
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.bytes, artwork);
      final saved = await store.localPath();
      await store.refresh();
      expect(calls, 1);
      for (final bad in [
        http.Response('not jpeg', 200),
        http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/map.jpg'},
        ),
        http.Response.bytes(artwork.sublist(0, 100), 200),
      ]) {
        response = bad;
        await store.refresh(force: true);
        expect(store.bytes, artwork);
        expect(await store.localPath(), saved);
        expect(await File(saved).readAsBytes(), artwork);
      }
      final restored = OfficialCampusMapStore(
        directory: () async => directory,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      addTearDown(restored.dispose);
      await restored.loadLocal();
      expect(restored.bytes, artwork);
      await File(saved).writeAsString('corrupt');
      final damaged = OfficialCampusMapStore(
        directory: () async => directory,
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      addTearDown(damaged.dispose);
      await damaged.loadLocal();
      expect(damaged.bytes, isNull);
      await expectLater(damaged.localPath(), throwsA(anything));
    },
  );
}
