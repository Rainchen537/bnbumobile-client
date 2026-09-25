import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/services/desktop_download_service.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/widgets/desktop_download_directory_tile.dart';

class _Picker extends FilePicker {
  String? selected;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => selected;
}

class _WidgetDownloads extends DesktopDownloadService {
  _WidgetDownloads(this.path);
  String path;
  String? selected;
  @override
  Future<String> directory(DesktopDownloadPurpose purpose) async => path;
  @override
  Future<String?> chooseDirectory(DesktopDownloadPurpose purpose) async {
    if (selected != null) path = selected!;
    return selected;
  }

  @override
  Future<String> resetDirectory(DesktopDownloadPurpose purpose) async =>
      path = '/Downloads';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory downloads;
  late Directory custom;
  late _Picker picker;
  late DesktopDownloadService service;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('bnbu-desktop-download-test-');
    downloads = await Directory('${root.path}/Downloads').create();
    custom = await Directory('${root.path}/Custom').create();
    picker = _Picker();
    service = DesktopDownloadService(
      picker: picker,
      downloadsProvider: () async => downloads,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  test(
    'single and archive choices are independent, persist, cancel and reset',
    () async {
      for (final purpose in DesktopDownloadPurpose.values) {
        expect(await service.directory(purpose), downloads.path);
      }
      picker.selected = custom.path;
      expect(
        await service.chooseDirectory(DesktopDownloadPurpose.single),
        custom.path,
      );
      expect(
        await service.directory(DesktopDownloadPurpose.archive),
        downloads.path,
      );
      final reloaded = DesktopDownloadService(
        picker: picker,
        downloadsProvider: () async => downloads,
      );
      expect(
        await reloaded.directory(DesktopDownloadPurpose.single),
        custom.path,
      );
      picker.selected = null;
      expect(
        await reloaded.chooseDirectory(DesktopDownloadPurpose.single),
        isNull,
      );
      expect(
        await reloaded.directory(DesktopDownloadPurpose.single),
        custom.path,
      );
      expect(
        await reloaded.resetDirectory(DesktopDownloadPurpose.single),
        downloads.path,
      );
    },
  );

  test(
    'publishes complete bytes without replacing existing files or leaving staging',
    () async {
      final source = await File(
        '${root.path}/source.pdf',
      ).writeAsString('synthetic PDF');
      final old = await File('${downloads.path}/file.pdf').writeAsString('old');
      final path = await service.save(
        sourcePath: source.path,
        fileName: 'file.pdf',
        isActive: () => true,
      );
      expect(path, isNot(old.path));
      expect(await File(path!).readAsString(), 'synthetic PDF');
      expect(await old.readAsString(), 'old');
      expect((await downloads.list().toList()).whereType<Directory>(), isEmpty);
      expect(
        await service.save(
          sourcePath: source.path,
          fileName: 'cancelled.pdf',
          isActive: () => false,
        ),
        isNull,
      );
      expect(await File('${downloads.path}/cancelled.pdf').exists(), isFalse);
    },
  );

  test(
    'missing choice and missing source fail without falling back or claiming success',
    () async {
      picker.selected = custom.path;
      await service.chooseDirectory(DesktopDownloadPurpose.single);
      await custom.delete();
      final source = await File(
        '${root.path}/source.txt',
      ).writeAsString('fixture');
      await expectLater(
        service.save(
          sourcePath: source.path,
          fileName: 'test.txt',
          isActive: () => true,
        ),
        throwsA(anything),
      );
      expect(await downloads.list().toList(), isEmpty);
      await service.resetDirectory(DesktopDownloadPurpose.single);
      await expectLater(
        service.save(
          sourcePath: '${root.path}/missing',
          fileName: 'test.txt',
          isActive: () => true,
        ),
        throwsA(anything),
      );
      expect(await downloads.list().toList(), isEmpty);
    },
  );

  test(
    'macOS scope is prepared, rechecked, committed once, then released',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel('test/desktop-downloads');
      final calls = <String>[];
      var active = true;
      var invalidate = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') {
          expect(call.arguments['purpose'], 'archive');
          if (invalidate) active = false;
          return 'handle';
        }
        if (call.method == 'commit') return '/Downloads/file.zip';
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const mac = DesktopDownloadService(channel: channel);
      expect(
        await mac.save(
          sourcePath: '/cache/file.zip',
          fileName: 'file.zip',
          purpose: DesktopDownloadPurpose.archive,
          isActive: () => active,
        ),
        '/Downloads/file.zip',
      );
      expect(calls, ['prepare', 'commit', 'discard']);
      calls.clear();
      invalidate = true;
      expect(
        await mac.save(
          sourcePath: '/cache/file.zip',
          fileName: 'file.zip',
          purpose: DesktopDownloadPurpose.archive,
          isActive: () => active,
        ),
        isNull,
      );
      expect(calls, ['prepare', 'discard']);
    },
  );

  test(
    'malicious response filenames are sanitized and MIME fills missing extensions',
    () {
      expect(
        resolvedDownloadFilename(
          suggested: 'view.php',
          contentType: 'application/pdf',
        ),
        'view.pdf',
      );
      expect(
        resolvedDownloadFilename(
          suggested: 'view.php',
          disposition: 'attachment; filename="../../a.pdf"',
        ),
        'a.pdf',
      );
      expect(
        resolvedDownloadFilename(
          suggested: 'slides',
          contentType:
              'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        ),
        'slides.pptx',
      );
    },
  );

  for (final width in [480.0, 900.0]) {
    testWidgets('directory controls remain usable at $width with long paths', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final widgetDownloads = _WidgetDownloads(downloads.path);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopDownloadDirectoryTile(
              purpose: DesktopDownloadPurpose.single,
              service: widgetDownloads,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(downloads.path), findsOneWidget);
      widgetDownloads.selected = custom.path;
      await tester.tap(find.byKey(const ValueKey('download-directory-single')));
      await tester.pumpAndSettle();
      expect(find.text(custom.path), findsOneWidget);
      await tester.tap(find.byTooltip('恢复系统下载目录'));
      await tester.pumpAndSettle();
      expect(find.text('/Downloads'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
