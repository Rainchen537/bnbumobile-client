import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:bnbu_me/services/page_backdrop_store.dart';
import 'package:bnbu_me/widgets/page_backdrop.dart';

Map<String, dynamic> manifest(int version, Map<String, String?> hashes) => {
  'schema_version': 1,
  'version': version,
  'slots': {
    for (final slot in PageBackdropStore.defaults.keys)
      slot: {
        'sha256': hashes[slot],
        'image': hashes[slot] == null
            ? null
            : '/v1/public/page-backgrounds/photos/${hashes[slot]}',
        'opacity': null,
      },
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'six-slot artwork stages without repaint, deduplicates, activates only on next launch and resets offline',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'page-backgrounds-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final png = img.encodePng(img.Image(width: 8, height: 8));
      final hash = sha256.convert(png).toString();
      var next = manifest(1, {
        for (final slot in PageBackdropStore.defaults.keys) slot: hash,
      });
      var requests = 0, changes = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('page-backgrounds')) {
          return http.Response(jsonEncode(next), 200);
        }
        requests++;
        return http.Response.bytes(png, 200);
      });
      PageBackdropStore store() => PageBackdropStore(
        client: client,
        directory: () async => dir,
        manifestUri: Uri.parse(
          'https://example.test/v1/public/page-backgrounds',
        ),
      );
      final first = store()..addListener(() => changes++);
      await first.checkForUpdate();
      expect(first.activeVersion, 0);
      expect(first.stagedVersion, 1);
      expect(first.bytesFor('user/light'), isNull);
      expect(changes, 0);
      expect(requests, 1);
      await first.checkForUpdate();
      expect(requests, 1);
      final second = store();
      await second.loadLocal();
      for (final slot in PageBackdropStore.defaults.keys) {
        expect(second.bytesFor(slot), png);
      }
      expect(second.activeVersion, 1);
      next = manifest(2, {});
      await second.checkForUpdate();
      expect(second.bytesFor('user/light'), png);
      final third = store();
      await third.loadLocal();
      expect(third.activeVersion, 2);
      expect(third.bytesFor('user/light'), isNull);
      first.dispose();
      second.dispose();
      third.dispose();
    },
  );
  test(
    'bad download, unknown slots, cross-origin and rollback never replace the last complete snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'page-backgrounds-reject-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final png = img.encodePng(img.Image(width: 8, height: 8));
      final hash = sha256.convert(png).toString();
      var next = manifest(3, {'user/light': hash});
      var mode = 0, requests = 0;
      final client = MockClient((r) async {
        if (mode == 1) throw const SocketException('offline');
        if (r.url.path.endsWith('page-backgrounds')) {
          return http.Response(jsonEncode(next), 200);
        }
        requests++;
        return http.Response.bytes(png, 200);
      });
      PageBackdropStore store() => PageBackdropStore(
        client: client,
        directory: () async => dir,
        manifestUri: Uri.parse(
          'https://example.test/v1/public/page-backgrounds',
        ),
      );
      final first = store();
      await first.checkForUpdate();
      mode = 1;
      final second = store();
      await second.checkForUpdate();
      expect(second.bytesFor('user/light'), png);
      mode = 0;
      next = manifest(4, {'user/light': 'a' * 64});
      await second.checkForUpdate();
      expect(second.stagedVersion, 3);
      next['slots']['user/light']['image'] = 'https://other.test/secret';
      final count = requests;
      await second.checkForUpdate();
      expect(requests, count);
      next = manifest(4, {})..['slots']['unknown/light'] = <String, String?>{};
      await second.checkForUpdate();
      expect(second.stagedVersion, 3);
      next = manifest(2, {});
      await second.checkForUpdate();
      expect(second.stagedVersion, 3);
      final third = store();
      await third.loadLocal();
      expect(third.bytesFor('user/light'), png);
      first.dispose();
      second.dispose();
      third.dispose();
    },
  );
  test(
    'source-specific cache cannot cross hosts; a corrupt slot falls back and repairs for next launch',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'page-backgrounds-corrupt-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final png = img.encodePng(img.Image(width: 8, height: 8)),
          hash = sha256.convert(png).toString();
      final client = MockClient(
        (r) async => r.url.path.endsWith('page-backgrounds')
            ? http.Response(jsonEncode(manifest(1, {'user/light': hash})), 200)
            : http.Response.bytes(png, 200),
      );
      PageBackdropStore store(String host) => PageBackdropStore(
        client: client,
        directory: () async => dir,
        manifestUri: Uri.parse('https://$host/v1/public/page-backgrounds'),
      );
      await store('example.test').checkForUpdate();
      final other = store('other.test');
      await other.loadLocal();
      expect(other.bytesFor('user/light'), isNull);
      final file =
          await dir
                  .list(recursive: true)
                  .where((f) => f.path.endsWith('.image'))
                  .first
              as File;
      await file.writeAsString('broken');
      final restarted = store('example.test');
      await restarted.loadLocal();
      expect(restarted.bytesFor('user/light'), isNull);
      await restarted.checkForUpdate();
      expect(restarted.bytesFor('user/light'), isNull);
      final repaired = store('example.test');
      await repaired.loadLocal();
      expect(repaired.bytesFor('user/light'), png);
    },
  );
  testWidgets(
    'all three pages use the appropriate bundled light and dark image',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('page-background-widget-'),
      ))!;
      addTearDown(() => dir.delete(recursive: true));
      final store = PageBackdropStore(
        client: MockClient((_) async => http.Response('', 503)),
        directory: () async => dir,
      );
      await tester.runAsync(store.start);
      for (final dark in [false, true]) {
        for (final page in ['directory', 'me-life', 'user']) {
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: SizedBox(
                width: 402,
                height: 200,
                child: PageBackdrop(page: page, store: store),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pumpAndSettle();
          final slot = '$page/${dark ? 'dark' : 'light'}';
          final image = tester.widget<Image>(
            find.byKey(ValueKey('page-backdrop-$slot')),
          );
          expect(
            (image.image as AssetImage).assetName,
            PageBackdropStore.defaults[slot],
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.start);
      store.dispose();
    },
  );
}
