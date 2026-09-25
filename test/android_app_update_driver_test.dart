import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/services/android_app_update_service.dart';
import 'package:bnbu_me/services/app_version_service.dart';
import 'package:bnbu_me/state/app_update_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late _Installer installer;
  late AndroidAppUpdateDriver driver;
  late AppUpdateController controller;
  var checks = 0;
  Future<void> setup() async {
    checks = 0;
    installer = _Installer();
    driver = AndroidAppUpdateDriver(
      service: AppVersionService(
        client: MockClient((_) async {
          checks++;
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'version': '1.2.4',
              'build_number': 6,
              'release_notes': <String>[],
              'platforms': {
                'android': {
                  'download_url':
                      'https://bnbu.yunwai.cloud/downloads/update.apk',
                  'sha256': 'a' * 64,
                  'size_bytes': 100,
                },
              },
            }),
            200,
          );
        }),
      ),
      packageInfoLoader: () async => PackageInfo(
        appName: 'BNBU.ME',
        packageName: 'me.bnbu.app',
        version: '1.2.3',
        buildNumber: '5',
      ),
      updateService: installer,
    );
    controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();
  }

  test(
    'download, permission denial and retry preserve the verified package',
    () async {
      await setup();
      final states = <Type>[];
      controller.addListener(() => states.add(controller.state.runtimeType));
      expect(controller.canDownloadInApp, isTrue);
      await controller.downloadAndInstall();
      expect(
        states,
        containsAllInOrder([
          AppUpdateDownloading,
          AppUpdateVerifying,
          AppUpdateInstalling,
          AppUpdateAwaitingInstall,
        ]),
      );
      expect(
        (controller.state as AppUpdateAwaitingInstall).permissionRequired,
        isTrue,
      );
      installer.permissionGranted = false;
      await controller.installUpdate(requestPermission: true);
      expect(installer.installs, 1);
      expect(
        (controller.state as AppUpdateAwaitingInstall).permissionRequired,
        isTrue,
      );
      installer.permissionGranted = true;
      await controller.installUpdate(requestPermission: true);
      expect(installer.downloads, 1);
      expect(installer.installs, 2);
      expect(
        (controller.state as AppUpdateAwaitingInstall).permissionRequired,
        isFalse,
      );
      expect(controller.statusLabel, '等待安装');
      await controller.checkAutomaticallyIfDue();
      expect(
        await controller.checkForUpdates(),
        AppUpdateCheckOutcome.available,
      );
      expect(checks, 1);
      expect(controller.state, isA<AppUpdateAwaitingInstall>());
      await controller
          .installUpdate(); // User cancelled the system screen and retries.
      expect(installer.installs, 3);
      expect(installer.downloads, 1);
    },
  );

  test(
    'repeated clicks and foreground checks do not replace an active download',
    () async {
      await setup();
      installer.pendingDownload = Completer<void>();
      final download = controller.downloadAndInstall();
      expect(controller.isBusy, isTrue);
      await controller.downloadAndInstall();
      await controller.checkForUpdates();
      expect(installer.downloads, 1);
      expect(checks, 1);
      expect(controller.state, isA<AppUpdateDownloading>());
      controller.cancelDownload();
      await download;
      expect(controller.state, isA<AppUpdateAvailable>());
      expect(installer.installs, 0);
      installer.pendingDownload = null;
      await controller.downloadAndInstall();
      expect(installer.downloads, 2);
      expect(installer.installs, 1);
    },
  );

  test(
    'native verification failure discards the artifact and offers download retry',
    () async {
      await setup();
      installer.installFailure = PlatformException(code: 'invalid_update');
      await controller.downloadAndInstall();
      expect(
        (controller.state as AppUpdateFailed).retryAction,
        AppUpdateRetryAction.download,
      );
      expect(driver.hasPendingUpdate, isFalse);
      installer.installFailure = null;
      await controller.downloadAndInstall();
      expect(installer.downloads, 2);
      expect(controller.state, isA<AppUpdateAwaitingInstall>());
    },
  );
}

class _Installer extends AndroidAppUpdateService {
  int downloads = 0;
  int installs = 0;
  bool permissionGranted = false;
  Object? installFailure;
  Completer<void>? pendingDownload;

  @override
  Future<File> download(
    AppUpdateRelease release, {
    required void Function(int) onProgress,
    required void Function() onVerifying,
  }) async {
    downloads++;
    onProgress(50);
    await pendingDownload?.future;
    onVerifying();
    return File('unused-synthetic-update.apk');
  }

  @override
  Future<AndroidInstallResult> install(
    File file,
    AppUpdateRelease release,
  ) async {
    installs++;
    if (installFailure != null) throw installFailure!;
    return permissionGranted
        ? AndroidInstallResult.installerOpened
        : AndroidInstallResult.permissionRequired;
  }

  @override
  Future<bool> requestInstallPermission() async => permissionGranted;

  @override
  void cancelDownload() {
    final pending = pendingDownload;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(AndroidUpdateCancelled());
    }
  }
}
