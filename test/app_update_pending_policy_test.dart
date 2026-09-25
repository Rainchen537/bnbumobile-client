import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/services/app_update_policy_service.dart';
import 'package:bnbu_me/services/android_app_update_service.dart';
import 'package:bnbu_me/state/app_update_controller.dart';

class PendingInstaller extends AndroidAppUpdateService {
  final downloadResult = Completer<File>();
  void Function(int)? progress;
  int installations = 0;
  @override
  Future<File> download(
    AppUpdateRelease release, {
    required void Function(int) onProgress,
    required void Function() onVerifying,
  }) {
    progress = onProgress;
    return downloadResult.future;
  }

  @override
  void cancelDownload() {
    if (!downloadResult.isCompleted) {
      downloadResult.completeError(AndroidUpdateCancelled());
    }
  }

  @override
  Future<AndroidInstallResult> install(
    File file,
    AppUpdateRelease release,
  ) async {
    installations++;
    return AndroidInstallResult.installerOpened;
  }
}

void main() {
  test(
    'in-flight progress respects new mandatory policy and withdrawal cancels old installation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final r = {
        'id': 'target',
        'platform': 'android',
        'channel': 'website',
        'version': '1.2.4.1',
        'native_version': '1.2.4.1',
        'build_number': 2,
        'bundle_id': 'example.app',
        'download_url': 'https://bnbu.yunwai.cloud/downloads/app.apk',
        'minimum_os': '',
        'sha256': 'a' * 64,
        'size_bytes': 100,
        'release_notes': <String>[],
        'release_notes_en': <String>[],
      };
      final p = {
        'platform': 'android',
        'channel': 'website',
        'target_id': 'target',
        'enabled': true,
        'minimum_supported_version': '',
        'minimum_supported_build': 0,
        'mandatory_after': '',
        'mandatory_reason': '',
        'mandatory_reason_en': '',
        'rollout_percent': 100,
        'triggers': {
          'startup': true,
          'resume': true,
          'login': true,
          'navigation': false,
          'periodic': true,
          'remote_event': true,
        },
        'timing': {
          'cache_seconds': 3600,
          'retry_seconds': 300,
          'defer_seconds': 86400,
          'repeat_seconds': 86400,
          'policy_valid_seconds': 86400,
          'event_debounce_seconds': 5,
        },
      };
      var payload = <String, dynamic>{
        'schema_version': 2,
        'revision': 1,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'releases': [r],
        'policies': [p],
      };
      Future<PackageInfo> info() async => PackageInfo(
        appName: 'Test',
        packageName: 'example.app',
        version: '1.2.4',
        buildNumber: '1',
      );
      final service = AppUpdatePolicyService(
        client: MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(jsonEncode(payload)), 200),
        ),
        packageInfoLoader: info,
      );
      final installer = PendingInstaller();
      final driver = AndroidAppUpdateDriver(
        service: service,
        packageInfoLoader: info,
        updateService: installer,
      );
      addTearDown(driver.dispose);
      await driver.check();
      final download = driver.downloadAndInstall();
      expect(driver.state, isA<AppUpdateDownloading>());
      payload['revision'] = 2;
      p['minimum_supported_version'] = '1.2.4.1';
      await driver.refreshPendingPolicy();
      expect(driver.state.release!.mandatory, true);
      installer.progress!(40);
      expect(driver.state.release!.mandatory, true);
      payload = {...payload, 'revision': 3, 'releases': [], 'policies': []};
      await driver.refreshPendingPolicy();
      await download;
      expect(driver.state, isA<AppUpdateUpToDate>());
      expect(installer.installations, 0);
      expect(driver.hasPendingUpdate, false);
    },
  );
}
