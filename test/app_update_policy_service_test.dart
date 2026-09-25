import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/models/app_update_policy.dart';
import 'package:bnbu_me/services/app_update_policy_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13, 12);
  Map<String, dynamic> catalog({
    String platform = 'android',
    String version = '1.2.4.1',
    String native = '1.2.4.1',
    int build = 2026091301,
    String minimum = '',
    String after = '',
    int revision = 1,
    String minimumOs = '',
  }) => {
    'schema_version': 2,
    'revision': revision,
    'generated_at': now.toIso8601String(),
    'releases': [
      {
        'id': 'target',
        'platform': platform,
        'channel': platform == 'ios' ? 'app_store' : 'website',
        'version': version,
        'native_version': native,
        'build_number': build,
        'bundle_id': 'me.bnbu.app',
        'download_url': platform == 'ios'
            ? 'https://apps.apple.com/app/id123456'
            : 'https://bnbu.yunwai.cloud/downloads/app.apk',
        'minimum_os': minimumOs,
        'sha256': 'a' * 64,
        'size_bytes': 100,
        'release_notes': ['修复'],
        'release_notes_en': ['Fix'],
      },
    ],
    'policies': [
      {
        'platform': platform,
        'channel': platform == 'ios' ? 'app_store' : 'website',
        'target_id': 'target',
        'enabled': true,
        'minimum_supported_version': minimum,
        'minimum_supported_build': 0,
        'mandatory_after': after,
        'mandatory_reason': '安全更新',
        'mandatory_reason_en': 'Security update',
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
      },
    ],
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<PackageInfo> info() => Future.value(
    PackageInfo(
      appName: 'BNBU.ME',
      packageName: 'me.bnbu.app',
      version: '1.2.4',
      buildNumber: '2026091201',
    ),
  );
  test(
    'four components compare numerically and omitted revision means zero',
    () {
      expect(
        ProductVersion.parse(
          '1.2.4',
        ).compareTo(ProductVersion.parse('1.2.4.0')),
        0,
      );
      expect(
        ProductVersion.parse(
          '1.2.4.10',
        ).compareTo(ProductVersion.parse('1.2.4.2')),
        greaterThan(0),
      );
      expect(
        ProductVersion.parse(
          '1.2.5',
        ).compareTo(ProductVersion.parse('1.2.4.9999')),
        greaterThan(0),
      );
      expect(() => ProductVersion.parse('1.2.4.01'), throwsFormatException);
    },
  );
  test(
    'optional becomes mandatory on a higher policy revision without a new artifact',
    () async {
      var json = catalog();
      final service = AppUpdatePolicyService(
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(json)), 200),
        ),
        packageInfoLoader: info,
        now: () => now,
      );
      addTearDown(service.dispose);
      expect(
        (await service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ))!.mandatory,
        false,
      );
      json = catalog(minimum: '1.2.4.1', revision: 2);
      final release = await service.check(
        platform: AppUpdatePlatform.android,
        installedBuildNumber: 2026091201,
      );
      expect(release!.mandatory, true);
      expect(release.nativeVersion, '1.2.4.1');
      expect(service.options.cacheSeconds, 3600);
    },
  );
  test(
    'deadline activates from cached policy and expired policy cannot lock users',
    () async {
      var time = now;
      final json = catalog(
        minimum: '1.2.4.1',
        after: now.add(const Duration(hours: 1)).toIso8601String(),
      );
      final service = AppUpdatePolicyService(
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(json)), 200),
        ),
        packageInfoLoader: info,
        now: () => time,
      );
      addTearDown(service.dispose);
      expect(
        (await service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ))!.mandatory,
        false,
      );
      time = now.add(const Duration(hours: 2));
      expect(
        (await service.restore(
          AppUpdatePlatform.android,
          2026091201,
        ))!.mandatory,
        true,
      );
      time = now.add(const Duration(days: 2));
      expect(
        await service.restore(AppUpdatePlatform.android, 2026091201),
        isNull,
      );
    },
  );
  test(
    'App Store compares publicly installable native version, not a newer build',
    () async {
      var json = catalog(platform: 'ios', native: '1.2.4');
      final service = AppUpdatePolicyService(
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(json)), 200),
        ),
        packageInfoLoader: info,
        now: () => now,
      );
      addTearDown(service.dispose);
      expect(
        await service.check(
          platform: AppUpdatePlatform.ios,
          installedBuildNumber: 2026091201,
        ),
        isNull,
      );
      json = catalog(platform: 'ios', native: '1.2.401', revision: 2);
      expect(
        await service.check(
          platform: AppUpdatePlatform.ios,
          installedBuildNumber: 2026091201,
        ),
        isNotNull,
      );
    },
  );
  test('incompatible OS cannot receive a mandatory target', () async {
    final service = AppUpdatePolicyService(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(catalog(minimum: '1.2.4.1', minimumOs: '15.0')),
          ),
          200,
        ),
      ),
      packageInfoLoader: info,
      now: () => now,
      systemVersion: '14.0',
    );
    addTearDown(service.dispose);
    expect(
      await service.check(
        platform: AppUpdatePlatform.android,
        installedBuildNumber: 2026091201,
      ),
      isNull,
    );
  });
  test(
    'withdrawal clears recommendation, stale revisions and unknown schema fail',
    () async {
      var json = catalog(minimum: '1.2.4.1');
      final service = AppUpdatePolicyService(
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(json)), 200),
        ),
        packageInfoLoader: info,
        now: () => now,
      );
      addTearDown(service.dispose);
      expect(
        await service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ),
        isNotNull,
      );
      json = {...catalog(revision: 2), 'policies': [], 'releases': []};
      expect(
        await service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ),
        isNull,
      );
      json = catalog(revision: 1);
      await expectLater(
        service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ),
        throwsFormatException,
      );
      json = {...catalog(revision: 3), 'schema_version': 3};
      await expectLater(
        service.check(
          platform: AppUpdatePlatform.android,
          installedBuildNumber: 2026091201,
        ),
        throwsFormatException,
      );
    },
  );
}
